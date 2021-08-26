{-# LANGUAGE PatternSynonyms      #-}
{-# LANGUAGE RankNTypes           #-}
{-# LANGUAGE StandaloneDeriving   #-}
{-# LANGUAGE UndecidableInstances #-}

module Swarm.AST where

import qualified Data.Functor.Const    as C
import           Data.Functor.Identity
import           Data.Text

import           Swarm.Types

type Var = Text

data Direction = Lft | Rgt | Back | Fwd | North | South | East | West
  deriving (Eq, Ord, Show, Read)

-- | Built-in function and command constants.
data Const
  = Wait
  | Move
  | Turn
  | Harvest
  | Build
  | Run
  | GetX
  | GetY
  | If
  | Force
  | Cmp CmpConst
  | Arith ArithConst
  deriving (Eq, Ord, Show)

data CmpConst = CmpEq | CmpNeq | CmpLt | CmpGt | CmpLeq | CmpGeq
  deriving (Eq, Ord, Show)

data ArithConst = Add | Sub | Mul | Div | Exp
  deriving (Eq, Ord, Show)

-- | The arity of a constant.
arity :: Const -> Int
arity Wait      = 0
arity Move      = 0
arity Turn      = 1
arity Harvest   = 0
arity Build     = 1
arity Run       = 1
arity GetX      = 0
arity GetY      = 0
arity If        = 3
arity Force     = 1
arity (Cmp _)   = 2
arity (Arith _) = 2

-- | Some constants are commands, which means a fully saturated
--   application of those constants counts as a value, and should not
--   be reduced further until they are to be executed (i.e. until they
--   meet an FExec frame).  Other constants just represent pure
--   functions; fully saturated applications of such constants should
--   be evaluated immediately.
isCmd :: Const -> Bool
isCmd (Cmp _)   = False
isCmd (Arith _) = False
isCmd c = c `notElem` funList
  where
    funList = [If, Force]

------------------------------------------------------------
-- Terms

-- | The Term' type is parameterized by a functor that expresses how
--   much type information we have.
--
--   - When f = C.Const (), we have no type information at all.
--   - When f = Maybe, we might have some type information (e.g. type
--     annotations supplied in the surface syntax)
--   - When f = Identity, we have all type information.
--
--   The type annotations are placed strategically to maintain the
--   following invariant: given the type of a term as input, we can
--   reconstruct the types of all subterms.  Additionally, some
--   annotations which would not otherwise be needed to maintain the
--   invariant (e.g. the type annotation on the binder of a lambda)
--   are there to allow the user to give hints to help type inference.

data Term' f
  = TUnit
  | TConst Const
  | TDir Direction
  | TInt Integer
  | TString Text
  | TBool Bool
  | TVar Var
  | TLam Var (f Type) (Term' f)
  | TApp (f Type) (Term' f) (Term' f)
  | TLet Var (f Type) (Term' f) (Term' f)
  | TBind (Maybe Var) (f Type) (Term' f) (Term' f)
  | TNop
  | TDelay (Term' f)
    -- TDelay has to be a special form --- not just an application of
    -- a constant --- so it can get special treatment during
    -- evaluation.

deriving instance Eq (f Type) => Eq (Term' f)
deriving instance Ord (f Type) => Ord (Term' f)
deriving instance Show (f Type) => Show (Term' f)

type Term = Term' Maybe
type ATerm = Term' Identity
type UTerm = Term' (C.Const ())

pattern ID :: a -> Identity a
pattern ID a = Identity a

pattern NONE :: C.Const () a
pattern NONE = C.Const ()

mapTerm' :: (f Type -> g Type) -> Term' f -> Term' g
mapTerm' _ TUnit              = TUnit
mapTerm' _ (TConst co)        = TConst co
mapTerm' _ (TDir di)          = TDir di
mapTerm' _ (TInt n)           = TInt n
mapTerm' _ (TString s)        = TString s
mapTerm' _ (TBool b)          = TBool b
mapTerm' _ (TVar x)           = TVar x
mapTerm' h (TLam x ty t)      = TLam x (h ty) (mapTerm' h t)
mapTerm' h (TApp ty2 t1 t2)   = TApp (h ty2) (mapTerm' h t1) (mapTerm' h t2)
mapTerm' h (TLet x ty t1 t2)  = TLet x (h ty) (mapTerm' h t1) (mapTerm' h t2)
mapTerm' h (TBind x ty t1 t2) = TBind x (h ty) (mapTerm' h t1) (mapTerm' h t2)
mapTerm' _ TNop               = TNop
mapTerm' h (TDelay t)         = TDelay (mapTerm' h t)

erase :: Term' f -> UTerm
erase = mapTerm' (const (C.Const ()))

bottomUp :: (Type -> ATerm -> ATerm) -> Type -> ATerm -> ATerm
bottomUp f ty@(_ :->: ty2) (TLam x xTy t) = f ty (TLam x xTy (bottomUp f ty2 t))
bottomUp f ty (TApp ity2@(ID ty2) t1 t2)
  = f ty (TApp ity2 (bottomUp f (ty2 :->: ty) t1) (bottomUp f ty2 t2))
bottomUp f ty (TLet x xTy@(ID ty1) t1 t2)
  = f ty (TLet x xTy (bottomUp f ty1 t1) (bottomUp f ty t2))
bottomUp f ty2 (TBind mx ia@(ID a) t1 t2)
  = f ty2 (TBind mx ia (bottomUp f (TyCmd a) t1) (bottomUp f ty2 t2))
bottomUp f ty (TDelay t) = f ty (TDelay (bottomUp f ty t))
bottomUp f ty t = f ty t

-- Apply a function to all the free occurrences of a variable.
mapFree :: Var -> (ATerm -> ATerm) -> ATerm -> ATerm
mapFree x f (TVar y)
  | x == y    = f (TVar y)
  | otherwise = TVar y
mapFree x f t@(TLam y ty body)
  | x == y = t
  | otherwise = TLam y ty (mapFree x f body)
mapFree x f (TApp ty t1 t2) = TApp ty (mapFree x f t1) (mapFree x f t2)
mapFree x f t@(TLet y ty t1 t2)
  | x == y = t
  | otherwise = TLet y ty (mapFree x f t1) (mapFree x f t2)
mapFree x f (TBind mx ty t1 t2)
  | Just y <- mx, x == y = TBind mx ty (mapFree x f t1) t2
  | otherwise = TBind mx ty (mapFree x f t1) (mapFree x f t2)
mapFree x f (TDelay t) = TDelay (mapFree x f t)
mapFree _ _ t = t
