--
-- Copyright © 2015 Christian Marie <christian@ponies.io>
--
-- The code in this file, and the program it is a part of, is
-- made available to you by its authors as open source software:
-- you can redistribute it and/or modify it under the terms of
-- the 3-clause BSD licence.
--

{-# LANGUAGE BangPatterns #-}

module Data.PhoneNumber
(
    -- * Types
    PhoneNumber(..),
    PhoneNumberRef,
    PhoneNumberType(..),
    PhoneNumberParseError(..),

    -- * Parsing
    parsePhoneNumber,
    parsePhoneNumberRef,

    -- * PhoneNumberRef accessors/utilities
    refCountryCode,
    refNationalNumber,
    refExtension,
    refType,

    -- * Utility
    convertAlphaCharacters,
) where

import           Data.ByteString           (ByteString, copy)
import           Data.PhoneNumber.LowLevel (PhoneNumber (..),
                                            PhoneNumberParseError (..),
                                            PhoneNumberRef,
                                            PhoneNumberType (..))
import qualified Data.PhoneNumber.LowLevel as LowLevel
import           Data.Word                 (Word64)
import           System.IO.Unsafe          (unsafePerformIO)

phoneUtilSingleton :: LowLevel.PhoneNumberUtil
phoneUtilSingleton = unsafePerformIO LowLevel.getPhoneNumberUtil
{-# NOINLINE phoneUtilSingleton #-}

-- | Try to parse a phone number, building a 'PhoneNumber' including commonly
-- accessed information.
--
-- This is marginally more expensive than parsing a 'PhoneNumberRef' with
-- 'parsePhoneNumberRef' and extracting just the fields that you need, although
-- the latter will allow you to retrieve more information such as the type of
-- number (which requires more underlying library calls).
parsePhoneNumber
    :: ByteString
    -- ^ The phone number to parse
    -> ByteString
    -- ^ A two letter country code for the default region to be assumed
    -> Either PhoneNumberParseError PhoneNumber
parsePhoneNumber phone_no default_region = unsafePerformIO $ do
    phone_ref <- LowLevel.newPhoneNumberRef
    r <- LowLevel.parsePhoneNumber phoneUtilSingleton phone_ref phone_no default_region
    traverse (\_ -> LowLevel.copyPhoneNumberRef phone_ref) r

-- | Try to parse a 'PhoneNumberRef', see the PhoneNumberRef accessors/utilities
-- section below for useful things to do with the result.
parsePhoneNumberRef
    :: ByteString
    -- ^ The phone number to parse
    -> ByteString
    -- ^ A two letter country code for the default region to be assumed
    -> Either PhoneNumberParseError PhoneNumberRef
parsePhoneNumberRef phone_no default_region = unsafePerformIO $ do
    phone_ref <- LowLevel.newPhoneNumberRef
    r <- LowLevel.parsePhoneNumber phoneUtilSingleton phone_ref phone_no default_region
    return $ phone_ref <$ r

refCountryCode :: PhoneNumberRef -> Maybe Word64
refCountryCode = unsafePerformIO . LowLevel.getCountryCode


refNationalNumber :: PhoneNumberRef -> Maybe Word64
refNationalNumber = unsafePerformIO . LowLevel.getNationalNumber

refExtension :: PhoneNumberRef -> Maybe ByteString
refExtension = unsafePerformIO . LowLevel.getExtension

refType :: PhoneNumberRef -> PhoneNumberType
refType = unsafePerformIO . LowLevel.getType phoneUtilSingleton

-- | Convert any alpha characters in a phone number to their equivalent keypad
-- numbers.
convertAlphaCharacters :: ByteString -> ByteString
convertAlphaCharacters number =
    let c = copy number
    in unsafePerformIO (c <$ LowLevel.unsafeConvertAlphaCharacters phoneUtilSingleton c)
