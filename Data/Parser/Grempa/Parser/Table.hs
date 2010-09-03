{-# LANGUAGE TemplateHaskell #-}
module Data.Parser.Grempa.Parser.Table where

import Data.Array
import Data.Dynamic
import Language.Haskell.TH.Lift

import Data.Parser.Grempa.Aux.Aux
import Data.Parser.Grempa.Grammar.Token

type StateI = Int
type RuleI  = Int
type StackI = Int
type ProdI  = Int

-- | Data type used in the action table to determine the next
--   parsing action depending on the input and current state
data Action s = Shift  StateI
              | Reduce RuleI ProdI StackI [Tok s]
              | Accept
              | Error [Tok s]
  deriving (Eq, Ord)

instance Show s => Show (Action s) where
    show (Shift i)        = "Shift "  ++ show i
    show (Reduce r p s _) = "Reduce " ++ show (r, p, s)
    show Accept           = "Accept"
    show (Error _)        = "Error"

  
unError :: Action s -> [Tok s]
unError (Error es) = es
unError _          = []

isReduce :: Action s -> Bool
isReduce (Reduce {}) = True
isReduce _           = False

$(deriveLift ''Action)

type ActionTable s = [(StateI, ([(Tok s, Action s)], Action s))]
type GotoTable   s = [((StateI, RuleI), StateI)]

type ActionFun s   = StateI -> Tok s -> Action s
type GotoFun   s   = StateI -> RuleI -> StateI

type ProdFunTable  = [((RuleI, ProdI), DynFun)]
type ProdFunFun    = RuleI  -> ProdI -> DynFun

prodFunToFun :: ProdFunTable -> ProdFunFun
prodFunToFun table r p = a ! (r, p)
  where a = listToArr (error "prodFun") table

data DynFun = DynFun Dynamic [Bool]

applDynFun :: DynFun -> [Dynamic] -> Dynamic
applDynFun (DynFun f (b:bs)) (a:as)
    | b         = applDynFun (DynFun (dynApp f a) bs) as
    | otherwise = applDynFun (DynFun f bs) as
applDynFun (DynFun f _) _ = f

