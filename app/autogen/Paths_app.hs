{-# LANGUAGE CPP #-}
{-# LANGUAGE NoRebindableSyntax #-}
{-# OPTIONS_GHC -fno-warn-missing-import-lists #-}
module Paths_app (
    version,
    getBinDir, getLibDir, getDynLibDir, getDataDir, getLibexecDir,
    getDataFileName, getSysconfDir
  ) where

import qualified Control.Exception as Exception
import Data.Version (Version(..))
import System.Environment (getEnv)
import Prelude

#if defined(VERSION_base)

#if MIN_VERSION_base(4,0,0)
catchIO :: IO a -> (Exception.IOException -> IO a) -> IO a
#else
catchIO :: IO a -> (Exception.Exception -> IO a) -> IO a
#endif

#else
catchIO :: IO a -> (Exception.IOException -> IO a) -> IO a
#endif
catchIO = Exception.catch

version :: Version
version = Version [0,1,0,0] []
bindir, libdir, dynlibdir, datadir, libexecdir, sysconfdir :: FilePath

bindir     = "/home/x/.cabal/bin"
libdir     = "/home/x/.cabal/lib/x86_64-linux-ghcjs-0.2.0-ghc7_10_3/app-0.1.0.0-Li0Gi2dxg3t5IbJ1j7d2RE-app"
dynlibdir  = "/home/x/.cabal/lib/x86_64-linux-ghcjs-0.2.0-ghc7_10_3"
datadir    = "/home/x/.cabal/share/x86_64-linux-ghcjs-0.2.0-ghc7_10_3/app-0.1.0.0"
libexecdir = "/home/x/.cabal/libexec/x86_64-linux-ghcjs-0.2.0-ghc7_10_3/app-0.1.0.0"
sysconfdir = "/home/x/.cabal/etc"

getBinDir, getLibDir, getDynLibDir, getDataDir, getLibexecDir, getSysconfDir :: IO FilePath
getBinDir = catchIO (getEnv "app_bindir") (\_ -> return bindir)
getLibDir = catchIO (getEnv "app_libdir") (\_ -> return libdir)
getDynLibDir = catchIO (getEnv "app_dynlibdir") (\_ -> return dynlibdir)
getDataDir = catchIO (getEnv "app_datadir") (\_ -> return datadir)
getLibexecDir = catchIO (getEnv "app_libexecdir") (\_ -> return libexecdir)
getSysconfDir = catchIO (getEnv "app_sysconfdir") (\_ -> return sysconfdir)

getDataFileName :: FilePath -> IO FilePath
getDataFileName name = do
  dir <- getDataDir
  return (dir ++ "/" ++ name)
