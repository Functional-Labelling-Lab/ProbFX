{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TypeOperators       #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Redundant return" #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE TypeApplications    #-}

{- | A variety of possible implementations of a [Hidden Markov Model (HMM)](https://en.wikipedia.org/wiki/Hidden_Markov_model).
-}

module HMM where

-- import           Control.Algebra (Has)
-- import           Control.Monad   ((>=>))
-- import           Data.Kind       (Constraint)
-- import           Env             (Assign ((:=)), Env, ConstructProduct, Observable, Observables,
--                                   nil, (<:>), ObsVar)
-- import           Inference.LW    as LW (lw)
-- import           Inference.SIM   as SIM (simulate)
-- import           Model           (Model, bernoulli', binomial, uniform)
-- import           Sampler         (Sampler)

-- -- | A HMM environment
-- type HMMEnv =
--   '[ "trans_p" ':= Double,    -- ^ parameter for transitioning between latent states
--      "obs_p"   ':= Double,    -- ^ parameter for projecting latent state to observation
--      "y"       ':= Int        -- ^ observation
--    ]

-- {- | HMM as a loop
-- -}
-- hmmFor :: (Observable env "y" Int, Observables env '["obs_p", "trans_p"] Double)
--   -- | number of HMM nodes
--   => Int
--   -- | initial HMM latent state
--   -> Int
--   -- | final HMM latent state
--   -> Model env sig m Int
-- hmmFor n x = do
--   -- Dist transition and observation parameters from prior distributions
--   trans_p <- uniform 0 1 #trans_p
--   obs_p   <- uniform 0 1 #obs_p
--   -- Iterate over @n@ HMM nodes
--   let hmmLoop i x_prev | i < n = do
--                             -- transition to next latent state
--                             dX <- fromEnum <$> bernoulli' trans_p
--                             let x = x_prev + dX
--                             -- project latent state to observation
--                             binomial x obs_p #y
--                             hmmLoop (i - 1) x
--                        | otherwise = return x_prev
--   hmmLoop 0 x

-- -- | Simulate from a HMM
-- simulateHMM :: Sampler (Int, Env HMMEnv)
-- simulateHMM = do
--   -- Specify model inputs
--   let x_0 = 0; n = 10
--   -- Specify model environment
--       env :: Env HMMEnv
--       env = #trans_p := [0.5] <:> #obs_p := [0.8] <:> #y := [] <:> nil
--   SIM.simulate env $ hmmFor n x_0

-- -- | Perform likelihood-weighting inference over HMM
-- inferLwHMM :: Sampler  [(Env HMMEnv, Double)]
-- inferLwHMM   = do
--   -- Specify model inputs
--   let x_0 = 0; n = 10
--   -- Specify model environment
--       env :: Env HMMEnv
--       env = #trans_p := [] <:> #obs_p := [] <:> #y := [0, 1, 1, 3, 4, 5, 5, 5, 6, 5] <:> nil
--   LW.lw 100 env $ hmmFor n x_0

-- {- | A modular HMM.
-- -}
-- transModel :: Double -> Int -> Model env sig m Int
-- transModel transition_p x_prev = do
--   dX <- fromEnum <$> bernoulli' transition_p
--   return (x_prev + dX)

-- obsModel :: Observable env "y" Int
--   => Double -> Int -> Model env sig m Int
-- obsModel observation_p x = do
--   y <- binomial x observation_p #y
--   return y

-- hmmNode :: Observable env "y" Int
--   => Double -> Double -> Int -> Model env sig m Int
-- hmmNode transition_p observation_p x_prev = do
--   x_i <- transModel transition_p x_prev
--   y_i <- obsModel observation_p x_i
--   return x_i

-- hmm :: (Observable env "y" Int, Observables env '["obs_p", "trans_p"] Double)
--   => Int -> (Int -> Model env sig m Int)
-- hmm n x = do
--   trans_p <- uniform 0 1 #trans_p
--   obs_p   <- uniform 0 1 #obs_p
--   foldr (>=>) return (replicate n (hmmNode trans_p obs_p)) x

-- {- | A higher-order, generic HMM.
-- -}
-- type TransModel env sig m params lat   = params -> lat -> Model env sig m lat
-- type ObsModel env sig m params lat obs = params -> lat -> Model env sig m obs

-- hmmGen :: Model env sig m ps1 -> Model env sig m ps2
--        -> TransModel env sig m ps1 lat -> ObsModel env sig m ps2 lat obs
--        -> Int -> lat -> Model env sig m lat
-- hmmGen transPrior obsPrior transModel obsModel n x_0 = do
--   ps1    <- transPrior
--   ps2    <- obsPrior
--   let hmmNode x = do
--                 x' <- transModel ps1 x
--                 y' <- obsModel ps2 x'
--                 return x'
--   foldl (>=>) return (replicate n hmmNode) x_0
