-----------------------------------------------------------------------------
-- |
-- Module      :  Swarm.Game.Recipes
-- Copyright   :  Brent Yorgey
-- Maintainer  :  byorgey@gmail.com
--
-- SPDX-License-Identifier: BSD-3-Clause
--
-- A recipe represents some kind of crafting process for transforming
-- some input entities into some output entities.  This module both
-- defines the 'Recipe' type and also defines the master list of
-- recipes for the game.
--
-----------------------------------------------------------------------------

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE TypeApplications  #-}

module Swarm.Game.Recipes where

import           Control.Lens
import           Data.Bifunctor      (second)
import           Data.IntMap         (IntMap)
import qualified Data.IntMap         as IM
import           Data.List           (foldl')
import           Data.Maybe          (listToMaybe)
import           Data.Text           (Text)
import qualified Data.Text           as T
import           Witch

import qualified Swarm.Game.Entities as E
import           Swarm.Game.Entity   (Count, Entity, Inventory)
import qualified Swarm.Game.Entity   as E
import           Swarm.Util

-- | An ingredient list is a list of entities with multiplicity.
type IngredientList = [(Count, Entity)]

-- | A recipe is just a list of input entities and a list of output
--   entities (both with multiplicity).  The idea is that it
--   represents some kind of \"crafting\" process where the inputs are
--   transformed into the outputs.
data Recipe = Recipe
  { _recipeInputs  :: IngredientList
  , _recipeOutputs :: IngredientList
  }
  deriving (Eq, Ord, Show)

makeLenses ''Recipe

prettyIngredientList :: IngredientList -> Text
prettyIngredientList = T.intercalate " + " . map prettyIngredient
  where
    prettyIngredient (n,e) = T.concat [ into @Text (show n), " ", number n (e ^. E.entityName) ]

-- | A map for quickly looking up which recipes can produce an entity
--   with a given hash value.  Built automatically from the 'recipeList'.
recipeMap :: IntMap [Recipe]
recipeMap = IM.fromListWith (++) (map (second (:[])) (concatMap outputs recipeList))
  where
    outputs r = [(e ^. E.entityHash, r) | (_, e) <- r ^. recipeOutputs]

-- | Look up a recipe for crafting a specific entity.
recipeFor :: Entity -> Maybe Recipe
recipeFor e = IM.lookup (e ^. E.entityHash) recipeMap >>= listToMaybe

-- | Figure out which ingredients (if any) are lacking from an
--   inventory to be able to carry out the recipe.
missingIngredientsFor :: Inventory -> Recipe -> [(Count, Entity)]
missingIngredientsFor inv (Recipe ins _)
  = filter ((>0) . fst) $ map (\(n,e) -> (n - E.lookup e inv, e)) ins

-- | Try to craft a recipe, deleting the recipe's inputs from the
--   inventory and adding the outputs. Return either a description of
--   which items are lacking, if the inventory does not contain
--   sufficient inputs, or an updated inventory if it was successful.
craft :: Recipe -> Inventory -> Either [(Count, Entity)] Inventory
craft r@(Recipe ins outs) inv = case missingIngredientsFor inv r of
  []      -> Right $
    foldl' (flip (uncurry E.insertCount)) (foldl' (flip (uncurry E.deleteCount)) inv ins) outs
  missing -> Left missing

-- | A big old list of all the recipes in the game.
recipeList :: [Recipe]
recipeList =
  [ Recipe
    [(1, E.tree)]
    [(2, E.branch), (1, E.log)]

  , Recipe
    [(1, E.log)]
    [(4, E.wood)]
  ]