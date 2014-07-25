module Velox.Job where

import Control.Applicative
import Control.Exception
import Control.Monad
import Control.Concurrent.Async
import Control.Concurrent.MVar
import Data.Map.Strict (Map)
import Data.Traversable (traverse)
import GHC.IO.Exception (AsyncException(ThreadKilled))
import System.FilePath

import qualified Data.List as L
import qualified Data.Map.Strict as M

import Velox.Artifact (ArtifactId(..))
import Velox.Dependencies (Dependencies, directDependencies, filterDependencies, reverseDependencies)
import Velox.Job.Task (Task(..), TaskContext(..), ArtifactAction, ProjectAction, runArtifactTasks, terminateTaskContext)
import Velox.Project (ProjectId, prjId)

data Job = Job { jobTasks :: [Task] }

data Plan = Plan
  { planProjectActions  :: [[(ProjectId,  [ProjectAction] )]]
  , planArtifactActions :: [[(ArtifactId, [ArtifactAction])]] }

artifactTasks :: [Task] -> Map ArtifactId [ArtifactAction]
artifactTasks tasks = M.fromListWith (++) xs where
  xs = tasks >>= \task -> case task of
    ArtifactTask i a  -> [(i, [a])]
    _                 -> []

projectTasks :: [Task] -> Map ProjectId [ProjectAction]
projectTasks tasks = M.fromListWith (++) xs where
  xs = tasks >>= \task -> case task of
    ProjectTask i a   -> [(i, [a])]
    _                 -> []

planArtifacts :: Dependencies -> [ArtifactId] -> [[ArtifactId]]
planArtifacts ds [] = []
planArtifacts ds xs = case zs of
    ([], [])    -> if null $ fst ys then [snd ys] else [snd ys, fst ys]
    (fzs, szs)  -> snd ys : (planArtifacts ds $ fst ys)
  where
    ys = f ds xs
    zs = f ds $ fst ys
    f ds xs = if null $ snd ys then ([], []) else ys where
      ys = L.break (\a -> null $ M.findWithDefault [] a directDeps) xs
      directDeps = directDependencies deps
      deps = filterDependencies xs ds


planJob :: Dependencies -> Job -> Plan
planJob ds job = Plan undefined $ f <$> planArtifacts ds artifactIds where
    f = (\xs -> (\x -> (x, M.findWithDefault [] x artifactTasks')) <$> xs)
    artifactIds = resolve $ M.keys artifactTasks' where
      resolve xs  = if zs == xs then xs else resolve zs where
        zs = L.nub (ys ++ xs)
        ys = (\x -> M.findWithDefault [] x reverseDeps) =<< xs
      reverseDeps = reverseDependencies ds
    artifactTasks' :: Map ArtifactId [ArtifactAction]
    artifactTasks' = artifactTasks $ jobTasks job
    projectTasks' :: Map ProjectId [ProjectAction]
    projectTasks' = projectTasks $ jobTasks job

runJob :: Dependencies -> Job -> IO ()
runJob ds j = do
  putStrLn "(start)"
  tcv <- newMVar $ TaskContext [] []
  res <- tryRun tcv
  case res of
    Left ThreadKilled -> do
      tc  <- takeMVar tcv
      terminateTaskContext tc
      putStrLn $ "(aborted)"
    _                 -> return ()
  where
    tryRun :: MVar TaskContext -> IO (Either AsyncException ())
    tryRun tcv = try $ do
      success         <- foldM (runStep tcv) True $ planArtifactActions $ planJob ds j
      putStrLn $ "(finish) " ++ show success where
        runStep tcv success xs = do
          swapMVar tcv $ TaskContext [] []
          case success of
            False -> return False
            True  -> do
              asyncs <- traverse (createAsync tcv . runArtifactTasks) xs
              xs <- traverse wait asyncs
              return $ and xs where
                createAsync :: MVar TaskContext -> IO a -> IO (Async a)
                createAsync v fx = do
                  tc    <- takeMVar v
                  async <- async fx
                  putMVar v $ tc { asyncs = (const () <$> async) : asyncs tc }
                  return async

