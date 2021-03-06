{-# LANGUAGE OverloadedStrings #-}

module HChip.Loader where

import HChip.Util

import Control.Exception
import Control.Monad
import Control.Monad.Error
import Data.Binary.Get
import Data.ByteString
import qualified Data.ByteString.Lazy as BSL
import Data.Bits
import Data.Digest.CRC32
import Data.Word
import Text.Printf

data Assembly = Assembly
  { version :: (Word8, Word8)
  , start :: Word16
  , rom :: ByteString 
  } deriving (Show)

parseAssembly :: Get Assembly
parseAssembly = do
  magic <- getByteString 4
  unless (magic == "CH16") $ fail "Invalid magic string."
  skip 1
  versionByte <- getWord8
  romSize <- getWord32le
  start <- getWord16le
  crc <- getWord32le
  rom <- getByteString (fromIntegral romSize)
  unless (crc32 rom == crc) $ fail "Invalid checksum."
  return $ Assembly (highNibble versionByte, lowNibble versionByte) start rom

loadAssembly :: BSL.ByteString -> Either String Assembly
loadAssembly bs = case runGetOrFail parseAssembly bs of
  Left (_, _, e) -> Left e
  Right (_, _, a) -> Right a