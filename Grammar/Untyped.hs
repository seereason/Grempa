{-# LANGUAGE GADTs, DoRec, PackageImports #-}
module Untyped where

import Control.Arrow
import Control.Applicative
import "monads-fd" Control.Monad.State
import qualified Data.Map as M
import Data.Map(Map)
import Data.Set(Set)
import qualified Data.Set as S

import Aux
import Table
import Token
import qualified Typed as T

-- | The recursive data types for untyped grammars
type Rule s = [Prod s]
type Prod s = [Symbol s]

data Symbol s
    = STerm s
    | SRule (RId s)
  deriving (Eq, Ord, Show)

data RId s = RId {rId :: Int, rIdRule :: Rule s}

instance Show (RId s) where
    show (RId i _) = show i
instance Eq (RId s) where
    RId i _ == RId j _ = i == j
instance Ord (RId s) where
    RId i _ `compare` RId j _ = i `compare` j

-- | Returns an untyped tree representation of a typed grammar
--   together with a mapping from rule and production number to
--   a dynamic containing the construction function of the typed
--   production
unType :: (s -> s') -> T.RId s a -> (RId s', ProdFuns)
unType cs = second snd . flip runState (M.empty, M.empty) . unTypeR cs
  where
    unTypeR :: (s -> s') -> T.RId s a -> State (Map Int (RId s'), ProdFuns) (RId s')
    unTypeR c (T.RId i r) = do
        (rids, funs) <- get
        case M.lookup i rids of
            Just x  -> return x
            Nothing -> do
                let newfuns = M.fromList
                            $ zip (zip (repeat i) [0..])
                                  (map T.getFun r)
                rec
                  put (M.insert i res rids, funs `M.union` newfuns)
                  res <- RId i <$> mapM ((reverse <$>) . unTypeP c) r
                return res
    unTypeP :: (s -> s') -> T.Prod s a -> State (Map Int (RId s'), ProdFuns) (Prod s')
    unTypeP c p = case p of
        T.PSeq  s ps -> liftM2 (:) (unTypeS c s) (unTypeP c ps)
        T.PSeqN s ps -> liftM2 (:) (unTypeS c s) (unTypeP c ps)
        T.PEnd _    -> return []
    unTypeS :: (s -> s') -> T.Symbol s a -> State (Map Int (RId s'), ProdFuns) (Symbol s')
    unTypeS c s = case s of
        T.STerm t -> return $ STerm (c t)
        T.SRule r -> SRule <$> unTypeR c r


instance Functor RId where
    fmap = flip evalState M.empty `dot` fmapR
      where
        fmapS :: (a -> b) -> Symbol a -> State (Map (RId a) (RId b)) (Symbol b)
        fmapS f (STerm s) = return $ STerm $ f s
        fmapS f (SRule r) = do
            done <- get
            case M.lookup r done of
              Just r' -> return $ SRule r'
              Nothing -> do
                  rec
                    put $ M.insert r res done
                    res <- fmapR f r
                  return $ SRule res
        fmapR :: (a -> b) -> RId a -> State (Map (RId a) (RId b)) (RId b)
        fmapR f (RId n r) = RId n <$> mapM (mapM (fmapS f)) r

-------------------------------------------------------------------------------
-- | Get all rules from a grammar by following a rule's non-terminals recursively
rules :: Token s => RId s -> [RId s]
rules = S.toList . recTraverseG rules' . S.singleton
  where
    rules' rs     = (res `S.union` rs, res)
      where
        res = S.unions $ map aux (S.toList rs)
    aux (RId _ r) = S.fromList [rid | p <- r, SRule rid <- p]

-- | Get all terminals (input symbols) from a list of rule IDs
terminals :: Token s => [RId s] -> [Symbol s]
terminals = concatMap (\(RId _ rs) -> [STerm s | as <- rs, STerm s <- as])

-- | Get all non-terminals (variables) from a list of rule IDs
nonTerminals :: Token s => [RId s] -> [Symbol s]
nonTerminals = map SRule

-- | Get the first tokens that a symbol eats
first :: Token s => Symbol s -> Set (ETok s)
first = first' S.empty

first' :: Token s => Set (RId s) -> Symbol s -> Set (ETok s)
first' _    (STerm s)              = S.singleton (ETok s)
first' done (SRule rid@(RId _ r)) = case rid `S.member` done of
    False -> S.unions $ map (firstProd' $ S.insert rid done) r
    True  -> S.empty

-- | Get the first tokens of a production
firstProd :: Token s => Prod s -> Set (ETok s)
firstProd = firstProd' S.empty

firstProd' :: Token s => Set (RId s) -> Prod s -> Set (ETok s)
firstProd' _    []     = S.singleton Epsilon
firstProd' done (x:[]) = first' done x
firstProd' done (x:xs) = case Epsilon `S.member` fx of
    True  -> S.union fx' (firstProd' done xs)
    False -> fx'
  where
    fx  = first' done x
    fx' = S.delete Epsilon fx

-- | Get all symbols that can follow a rule,
--   also given the start rule and a list of all rules
follow :: Token s => RId s -> RId s -> [RId s] -> Set (Tok s)
follow = follow' S.empty

follow' :: Token s => Set (RId s) -> RId s -> RId s -> [RId s] -> Set (Tok s)
follow' done rid startrid rids = case rid `S.member` done of
    True  -> S.empty
    False -> S.unions $
        (if rid == startrid then S.singleton RightEnd else S.empty) :
        [followProd prod a | a@(RId _ prods) <- rids, prod <- prods]
  where
    followProd []       _ = S.empty
    followProd (b:beta) a
        | b == SRule rid = case Epsilon `S.member` firstbeta of
            True  -> follow' (S.insert rid done)
                             a startrid rids `S.union` rest
            False -> rest
        | otherwise      = followProd beta a
      where
        firstbeta = firstProd beta
        rest      = S.map (Tok . unETok) $ S.delete Epsilon firstbeta
