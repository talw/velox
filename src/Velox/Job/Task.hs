module Velox.Job.Task where

import Control.Concurrent.Async
import Data.Traversable (traverse)
import System.Process (ProcessHandle, terminateProcess)

import Velox.Artifact (ArtifactId)
import Velox.Project (ProjectId)

-- TODO Remove
import Control.Concurrent (threadDelay)

data Task
  = ArtifactTask  ArtifactId  ArtifactAction
  | ProjectTask   ProjectId   ProjectAction
  deriving (Eq, Show)

data ArtifactAction
  = TypeCheck [FilePath]
  | Build
  deriving (Eq, Ord, Show)

data ProjectAction
  = Configure
  deriving (Eq, Ord, Show)

data Action
  = Success
  | Failure String

-- TODO Optimize actions!
runArtifactTasks :: (ArtifactId, [ArtifactAction]) -> IO Bool
runArtifactTasks (a, fps) = do
  putStrLn (show a ++ " START")
  threadDelay $ 1000 * 1000
  putStrLn (show a ++ " FINISH")
  return True

runProjectTasks :: (ProjectId, [ProjectAction]) -> IO Bool
runProjectTasks = undefined

data TaskContext = TaskContext
  { asyncs    :: [Async ()]
  , processes :: [ProcessHandle] }

terminateTaskContext :: TaskContext -> IO ()
terminateTaskContext tc = do
  traverse cancel $ asyncs tc
  traverse terminateProcess $ processes tc
  return ()

