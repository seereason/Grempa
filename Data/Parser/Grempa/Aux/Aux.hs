module Data.Parser.Grempa.Aux.Aux where
import Control.Monad.State
import Data.Array
import Data.Map(Map)
import qualified Data.Map as M
import Data.Maybe
import Data.Set(Set)
import qualified Data.Set as S

setFromJust :: Ord a => Set (Maybe a) -> Set a
setFromJust = S.map fromJust . S.delete Nothing

-- | Traverse a recursive data structure without doing the same thing more
--   than once.
--   Takes a function returning (result, candidates), then the initial set
recTraverseG :: (Ord a, Ord b) => (Set a -> (Set b, Set a)) -> Set a -> Set b
recTraverseG = recTraverseG' S.empty
  where
    recTraverseG' done f x = if S.null cand'
                              then res
                              else res `S.union` recTraverseG' done' f cand'
      where (res, cand) = f x
            cand'       = cand S.\\ done'
            done'       = done `S.union` x

recTraverse :: Ord a => (Set a -> Set a) -> Set a -> Set a
recTraverse f = recTraverseG $ split . f
  where split x = (x, x)

dot :: (c -> d) -> (a -> b -> c) -> a -> b -> d
dot = (.) . (.)

type Done k v = State (Map k v)
type DoneA k v = Done k v v

getDone :: Ord k => k -> Done k v (Maybe v)
getDone = gets . M.lookup

ifNotDoneG :: Ord k => k -> (v -> a) -> Done k v a -> Done k v a
ifNotDoneG k ifDone action = do
    done <- getDone k
    case done of
        Just x  -> return $ ifDone x
        Nothing -> action

ifNotDone :: Ord k => k -> DoneA k v -> DoneA k v
ifNotDone = flip ifNotDoneG id

putDone :: Ord k => k -> v -> Done k v ()
putDone = modify `dot` M.insert

evalDone :: Done k v a -> a
evalDone = flip evalState M.empty

-- | Convert a mapping to an array
--   Uses minimum and maximum, which means that the Ix and Num instances
--   must comply.
class IxMinMax a where
    ixMax :: [a] -> a
    ixMin :: [a] -> a

instance IxMinMax Int where
    ixMax = maximum
    ixMin = minimum

instance (IxMinMax a, IxMinMax b) => IxMinMax (a, b) where
    ixMax xs = (ixMax fs, ixMax ss)
      where (fs, ss) = unzip xs
    ixMin xs = (ixMin fs, ixMin ss)
      where (fs, ss) = unzip xs

listToArr :: (IxMinMax k, Ix k) => [(k, v)] -> Array k v
listToArr ass = array (ixMin keys, ixMax keys) ass
  where keys = map fst ass

--mapToArr :: (IxMinMax k, Ix k) => Map k v -> Array k v
--mapToArr m = listToArr $ M.toList m

