{-# LANGUAGE GADTs, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FunctionalDependencies, FlexibleInstances #-}
module Grammar
  ( Grammar, runGrammar
  , (+++), (|||)
  , symbol, rule
  , mkRule
  , ($::=)
  ) where

import Control.Applicative
import Control.Monad
import Control.Monad.Identity
import Control.Monad.State
import Control.Monad.Writer
import Unsafe.Coerce

--------------------------------------------------------------------------
-- Interface

($::=) :: (a -> b) -> P s a -> Grammar s (GId s b)
f $::= p = mkRule $ f <$> p

(|||) :: P s a -> P s a -> P s a
(|||) = (:|:)

(+++) :: P s a -> P s b -> P s (a,  b)
(+++) = (:+:)

rule :: GId s a -> P s a
rule = Rule

symbol :: s -> P s s
symbol = Symbol

infixl 5 :|:
infixl 5 |||
infixl 6 :+:
infixl 6 +++
infixl 3 $::=

instance Functor (P s) where
  fmap = F

mkRule :: P s p -> Grammar s (GId s p)
mkRule p = do
    v <- newName
    addRule v p
    return v

--------------------------------------------------------------------------
-- Grammar rules (Parser)

data P s a where
  Symbol :: s -> P s s
  (:|:)  :: P s a -> P s a -> P s a
  (:+:)  :: P s a -> P s b -> P s (a, b)
  F      :: (a -> b) -> P s a -> P s b
  Rule   :: GId s a -> P s a

instance Show s => Show (P s a) where
  show p = case p of
      Symbol s -> show s
      p :|: q  -> show p ++ " | " ++ show q
      p :+: q  -> show p ++ " "   ++ show q 
      F f p    -> show p
      Rule id  -> "RULE(" ++ show id ++ ")"

--------------------------------------------------------------------------
-- Grammar

data GId s a = GId Integer
  deriving (Show)

class Equals a b where
  (=?=) :: a -> b -> Bool

instance Equals (GId s a) (GId s b) where
  GId x =?= GId y = x == y

data Binding s where
  Binding :: GId s p -> P s p -> Binding s

instance Show s => Show (Binding s) where
  show (Binding id p) = show id ++ " ::= " ++ show p

data Env s = Env
  { bindings :: [Binding s]
  , names    :: [Integer]
  }

newtype Grammar s a = Grammar 
    { unGrammar 
      :: StateT (Env s)
                Identity
                a
    } deriving ( Monad, MonadFix, Functor
               , MonadState (Env s)
               )

defaultEnv :: Env s
defaultEnv = Env {bindings = [], names = [1..]}

runGrammar :: Grammar s a -> [Binding s]
runGrammar = bindings
           . runIdentity
           . flip execStateT defaultEnv
           . unGrammar

addRule :: GId s p -> P s p -> Grammar s ()
addRule v p = do
    st <- get
    put st {bindings = Binding v p : bindings st}

newName :: Grammar s (GId s p)
newName = do
    st <- get
    let v:vs = names st
    put st {names = vs}
    return $ GId v

getRule :: GId s p -> Grammar s (P s p)
getRule x = findRule x <$> gets bindings
  where
    findRule :: GId s p -> [Binding s] -> P s p
    findRule x (Binding x' p : bs) | x =?= x'  = unsafeCoerce p -- Hack!
                                   | otherwise = findRule x bs

--------------------------------------------------------------------------
-- Left recursion elimination
{-
elim :: GId s p -> Grammar s ()
elim x = do
    p <- getRule x
    --case leftMost p of
        --F f p
    return ()

class LeftMost a b | a -> b where
  leftMost :: P s a -> P s b

instance LeftMost (a, b) a where
  leftMost (p :+: _) = p

instance LeftMost a a where
  leftMost (p :|: _)    = p
  leftMost p@(Symbol _) = p
  leftMost p@(Rule _)   = p
  --leftMost _ = undefined


--instance LeftMost a b

  Symbol :: s -> P s s
  (:|:)  :: P s a -> P s a -> P s a
  (:+:)  :: P s a -> P s b -> P s (a, b)
  F      :: (a -> b) -> P s a -> P s b
  Rule   :: GId s a -> P s a
  -}
