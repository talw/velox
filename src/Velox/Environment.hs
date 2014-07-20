module Velox.Environment where

import Control.Arrow ((&&&))
import Control.Applicative ((<$>))
import Control.Monad (join)
import Data.Char (toUpper)
import Data.Function (on)
import Data.Map.Strict (Map)
import Data.Maybe (maybeToList)
import Data.Traversable (traverse)
import Distribution.Text (display)
import GHC.Exts (sortWith)
import System.Directory (canonicalizePath, doesDirectoryExist)
import System.FilePath ((</>))

import qualified Data.List as List
import qualified Data.Map.Strict as Map

import Distribution.Sandbox.Utils (findSandbox, readSandboxSources)
import Velox.Build (Build, BuildId, bldId, bldKind)
import Velox.Dependencies (ReverseDependencies, resolveReverseDependencies)
import Velox.Project (Project(..), ProjectId, findProject, findProjects, prjBuilds, prjId, prjName)
import Velox.Workspace (Workspace(..), findWorkspace, wsDir)

data Env = Env
  { workspace :: Workspace
  , projects :: [Project]
  , reverseDependencies :: ReverseDependencies
  , leader :: Maybe Project
  , isStandalone :: Bool }

data LoadError = NoAnchor | NoSandbox FilePath
  deriving (Eq, Show)

loadEnv :: IO (Either LoadError Env)
loadEnv = do
  fp <- canonicalizePath "."
  ws <- findWorkspace fp
  case ws of
    Nothing -> do
      prjDesc <- findProject fp
      case prjDesc of
        Nothing      -> return $ Left NoAnchor
        Just prjDesc -> do
          prj <- createStandalone fp prjDesc
          return prj
    Just ws -> do
      prjs <- findProjects $ wsDir ws
      leader <- findProject fp
      return . Right $ Env ws (concat [maybeToList leader, prjs]) (resolveReverseDependencies prjs) leader False
  where
    createStandalone :: FilePath -> Project -> IO (Either LoadError Env)
    createStandalone fp prj = do
      sandboxPath <- findSandbox fp
      case sandboxPath of
        Nothing   -> return . Left $ NoSandbox fp
        Just p    -> do
          xs <- readSandboxSources p
          ys <- traverse findProject xs
          let prjs = prj:(maybeToList =<< ys)
          return . Right $ Env (Workspace fp p) prjs (resolveReverseDependencies prjs) (Just prj) True
      where
        sandboxPath = fp </> ".cabal-sandbox"
