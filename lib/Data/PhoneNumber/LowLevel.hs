--
-- Copyright © 2015 Christian Marie <christian@ponies.io>
--
-- The code in this file, and the program it is a part of, is
-- made available to you by its authors as open source software:
-- you can redistribute it and/or modify it under the terms of
-- the 3-clause BSD licence.
--

-- | Low level phone number handling, more closely matches the underlying
-- libphonenumber API.
{-# LANGUAGE ViewPatterns #-}

module Data.PhoneNumber.LowLevel
(
    -- * Data types
    PhoneNumber(..),
    PhoneNumberParseError(..),
    PhoneNumberUtil(..),

    -- * References and parsing
    getPhoneNumberUtil,
    newPhoneNumberRef,
    parsePhoneNumber,

    -- * Extracting usable information
    copyPhoneNumberRef,

    getCountryCode,
    getNationalNumber,
    getExtension,
) where

import Data.PhoneNumber.FFI
import Foreign.ForeignPtr(withForeignPtr, newForeignPtr)
import Foreign.Ptr(Ptr)
import Data.Word
import Data.ByteString(ByteString, useAsCStringLen)
import Data.ByteString.Unsafe(unsafePackMallocCString)
import Control.Monad

-- | There was a problem parting your phone number. For now, if you want to
-- know what the Int here means, you'll need to look at the ErrorType enum in
-- the underlying library.
data PhoneNumberParseError = PhoneNumberParseError Int
  deriving (Eq, Show)

-- | A data type representation of a phone number, you can build one of these
-- with copyPhoneNumberRef.
data PhoneNumber =
    PhoneNumber {
        countryCode    :: Maybe Word64,
        nationalNumber :: Maybe Word64,
        extension      :: Maybe ByteString
    } deriving (Eq, Show)


-- | Grab the singleton PhoneNumberUtil class instance, needed to do useful
-- things with libphonenumber
getPhoneNumberUtil :: IO PhoneNumberUtil
getPhoneNumberUtil =
    PhoneNumberUtil <$> c_phone_number_util_get_instance

-- | Create a mutable reference to a PhoneNumber (C++ class) instance.
newPhoneNumberRef :: IO PhoneNumberRef
newPhoneNumberRef = do
    ptr <- c_phone_number_ctor
    PhoneNumberRef <$> newForeignPtr c_phone_number_dtor ptr

-- | Parse a phone number.
parsePhoneNumber
    :: PhoneNumberUtil
    -- ^ The singleton PhoneNumberUtil reference
    -> PhoneNumberRef
    -- ^ The reference to be mutably updated 
    -> ByteString
    -- ^ The bytestring to parse as a phone number
    -> ByteString
    -- ^ The default region to assume numbers are from, if ambiguous. e.g. "AU"
    -- for Australia
    -> IO (Either PhoneNumberParseError ())
parsePhoneNumber (PhoneNumberUtil util_ptr) (PhoneNumberRef f_ptr) number region =
    useAsCStringLen number $ \(number_str, fromIntegral -> number_len) ->
    useAsCStringLen region $ \(region_str, fromIntegral -> region_len) ->
    withForeignPtr f_ptr $ \ptr -> do
        e <- c_phone_number_util_parse util_ptr number_str number_len region_str region_len ptr
        return $ checkError (fromIntegral e)
  where
    -- TODO: This is actually a an ErrorType enum, we could translate errors to
    -- more useful ones.
    checkError 0 = Right ()
    checkError e = Left $ PhoneNumberParseError e

-- | Read the country code from a PhoneNumberRef
getCountryCode :: PhoneNumberRef -> IO (Maybe Word64)
getCountryCode =
    (fmap . fmap) fromIntegral . maybeFetch c_phone_number_has_country_code c_phone_number_get_country_code

-- | Read the national number (the phone number itself) from a PhoneNumberRef
getNationalNumber :: PhoneNumberRef -> IO (Maybe Word64)
getNationalNumber =
    (fmap . fmap) fromIntegral . maybeFetch c_phone_number_has_national_number c_phone_number_get_national_number

-- | Read the extension (e.g. 12345678x123) from a PhoneNumberRef
getExtension :: PhoneNumberRef -> IO (Maybe ByteString)
getExtension =
    maybeFetch c_phone_number_has_extension c_phone_number_get_extension >=> traverse unsafePackMallocCString

-- | Copy fields from a 'PhoneNumberRef' and create a 'PhoneNumber'
copyPhoneNumberRef :: PhoneNumberRef -> IO PhoneNumber
copyPhoneNumberRef ref =
    PhoneNumber <$> getCountryCode ref
                <*> getNationalNumber ref
                <*> getExtension ref

-- * Helpers

maybeFetch
    :: (Ptr PhoneNumberRef -> IO Bool)
    -> (Ptr PhoneNumberRef -> IO a)
    -> PhoneNumberRef
    -> IO (Maybe a)
maybeFetch p f (PhoneNumberRef f_ptr) =
    withForeignPtr f_ptr $ \ptr -> do
        r <- p ptr
        if r
            then Just <$> f ptr
            else return Nothing