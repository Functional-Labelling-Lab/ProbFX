{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilyDependencies #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Redundant return" #-}

{- |
     This demonstrates:
      - The [SIR](https://en.wikipedia.org/wiki/Compartmental_models_in_epidemiology) model for modelling
        the transition between Susceptible (S), Infected (I), and Recovered (R) individuals during an epidemic.
        We model this as a Hidden Markov Model, where the latent states are the true values of S, I, and R,
        and the observations are the reported number of infections (𝜉).
      - Extending the SIR to the SIRS model where recovered individuals (R) can become susceptible (S) again.
      - Extending the SIRS to the SIRSV model where susceptible individuals (S) can become vaccinated (V).

    For convenience, this makes use of 'Control.Lens' accessors and the 'Data.Extensible' library.
 -}

module SIRModular where

import Data.Extensible ( mkField, Record, Lookup, type (>:), (@=), (<:), emptyRecord, Assoc ((:>)) )
import Prog ( Member )
import Control.Lens ( (&), (^.), (.~) )
import Effects.Writer ( Writer, tellM, handleWriterM )
import Model ( Model, beta, binomial', gamma, poisson )
import Control.Monad ( (>=>) )
import Env ( Observables, Observable, Assign ((:=)), (<:>), nil)
import HMM ( ObsModel, TransModel, hmmGen )
import GHC.TypeLits ( Symbol )
import Data.Kind (Constraint)
import Sampler
import Inference.SIM as SIM

-- | A type family for conveniently specifying multiple fields of the same type
type family Lookups env (ks :: [Symbol]) a :: Constraint where
  Lookups env (x ': xs) a = (Lookup env x a, Lookups env xs a)
  Lookups env '[] a = ()

-- | HMM latent states (SIRV)
mkField "s" -- ^ susceptible individuals
mkField "i" -- ^ infected individuals
mkField "r" -- ^ recovered individuals
mkField "v" -- ^ vaccinated individuals

type Popl  = Record '[
    "s" >: Int
  , "i" >: Int
  , "r" >: Int
  , "v" >: Int]

-- | HMM observations (𝜉)
type Reported = Int


{- | SIR model -}
-- | SIR transition prior
transPriorSIR :: Observables env '["β",  "γ"] Double
  => Model env ts (Double, Double)
transPriorSIR = do
  pBeta  <- gamma 2 1 #β
  pGamma <- gamma 1 (1/8) #γ
  return (pBeta, pGamma)

-- | Transition model from S and I
transSI :: Lookups popl '["s", "i", "r"] Int => TransModel env ts Double (Record popl)
transSI  beta popl = do
  let (s_0, i_0, r_0 ) = (popl ^. s,  popl ^. i,  popl ^. r)
      pop = s_0 + i_0 + r_0
  dN_SI <- binomial' s_0 (1 - exp ((-beta * fromIntegral i_0) / fromIntegral pop))
  return $ popl & s .~ (s_0 - dN_SI)
                & i .~ (i_0 + dN_SI)

-- | Transition model from I and R
transIR :: Lookups popl '["i", "r"] Int => TransModel env ts Double (Record popl)
transIR  gamma popl = do
  let (i_0, r_0) = (popl ^. i,  popl ^. r)
  dN_IR <- binomial' i_0 (1 - exp (-gamma))
  return $ popl & i .~ (i_0 - dN_IR)
                & r .~ (r_0 + dN_IR)

-- | Transition model from S to I, and I to R
transSIR :: (Member (Writer [Record popl]) ts, Lookups popl '["s", "i", "r"] Int)
  => TransModel env ts (Double, Double) (Record popl)
transSIR (beta, gamma) popl = do
  popl <- (transSI beta >=> transIR gamma) popl
  tellM [popl]  -- a user effect for writing each latent SIR state to a stream [Record popl]
  return popl

-- | SIR observation prior
obsPriorSIR :: Observables env '["ρ"] Double
  => Model env ts Double
obsPriorSIR = beta 2 7 #ρ

-- | SIR observation model
obsSIR :: Lookup s "i" Int => Observable env "𝜉" Int
  => ObsModel env ts Double (Record s) Reported
obsSIR rho popl  = do
  let i_0 = popl ^. i
  poisson (rho * fromIntegral i_0) #𝜉

-- | SIR as HMM
hmmSIR :: forall popl es env. (Member (Writer [Record popl]) es,
           Lookups popl '["s", "i", "r"] Int, Observable env "𝜉" Int, Observables env '["ρ", "β", "γ"] Double)
  => Record popl -> Int -> Model env es (Record popl, [Record popl])
hmmSIR p n  = handleWriterM @([Record popl]) $ hmmGen transPriorSIR obsPriorSIR transSIR obsSIR n p

-- simulateSIR :: Sampler ([(Int, Int, Int)], [Reported])
-- simulateSIR = do
--   -- Specify model input of 762 susceptible and 1 infected
--   let sir_0  :: Record  '[ "s" ':> Int, "i" ':> Int, "r" ':> Int]    = #s @= 762 <: #i @= 1 <: #r @= 0 <: emptyRecord
--   -- Specify model environment
--       sim_env_in = #β := [0.7] <:> #γ := [0.009] <:> #ρ := [0.3] <:> #𝜉 := [] <:> nil
--   -- Simulate an epidemic over 100 days
--   ((_, sir_trace), sim_env_out) <- SIM.simulate (hmmSIR @( [ "s" ':> Int, "i" ':> Int, "r" ':> Int]) sir_0 ) sim_env_in  100
--   -- Get the observed infections over 100 days
--   -- let 𝜉s :: [Reported] = get #𝜉 sim_env_out
--   -- -- Get the true SIR values over 100 days
--   --     sirs = map (\sir -> (sir ^. s, sir ^. i, sir ^. r)) sir_trace
--   -- return (sirs, 𝜉s)
--   undefined

{- | SIRS model -}
-- | SIRS transition prior
transPriorSIRS :: Observables env '["β", "η", "γ"] Double
  => Model env ts (Double, Double, Double)
transPriorSIRS = do
  (pBeta, pGamma)  <- transPriorSIR
  pEta <- gamma 1 (1/8) #η
  return (pBeta, pGamma, pEta)

-- | Transition model from S to R
transRS :: Lookups popl '["s", "r"] Int => TransModel env ts Double (Record popl)
transRS eta popl = do
  let (r_0, s_0) = (popl ^. r,  popl ^. s)
  dN_RS <- binomial' r_0 (1 - exp (-eta))
  return $ popl & r .~ (r_0 - dN_RS)
                & s .~ (s_0 + dN_RS)

-- | Transition model from S to I, I to R, and R to S
transSIRS :: Lookups popl '["s", "i", "r"] Int => TransModel env es (Double, Double, Double) (Record popl)
transSIRS (beta, gamma, eta) = transSI beta >=> transIR gamma >=> transRS eta

-- | SIRS as HMM
hmmSIRS :: (Member (Writer [Record popl]) es,
            Lookups popl '["s", "i", "r"] Int,
            Observables env '["𝜉"] Int, Observables env '["β", "η", "γ", "ρ"] Double)
  => Int -> Record popl -> Model env es (Record popl, [Record popl])
hmmSIRS n = handleWriterM . hmmGen transPriorSIRS obsPriorSIR transSIRS obsSIR n


{- | SIRSV model -}
-- | SIRSV transition prior
transPriorSIRSV :: Observables env '["β", "γ", "ω", "η"] Double
  => Model env ts (Double, Double, Double, Double)
transPriorSIRSV  = do
  (pBeta, pGamma, pEta) <- transPriorSIRS
  pOmega <- gamma 1 (1/16) #ω
  return (pBeta, pGamma, pEta, pOmega)

-- | Transition model from S to V
transSV :: Lookups popl '["s", "v"] Int => TransModel env es Double (Record popl)
transSV omega popl  = do
  let (s_0, v_0) = (popl ^. s,  popl ^. v)
  dN_SV <- binomial' s_0 (1 - exp (-omega))
  return $ popl & s .~ (s_0 - dN_SV)
                & v .~ (v_0 + dN_SV)

-- | Transition model from S to I, I to R, R to S, and S to V
transSIRSV :: Lookups popl '["s", "i", "r", "v"] Int => TransModel env ts (Double, Double, Double, Double) (Record popl)
transSIRSV (beta, gamma, eta, omega) =
  transSI beta >=> transIR gamma >=> transRS eta  >=> transSV omega

-- | SIRSV as HMM
hmmSIRSV :: (Member (Writer [Record popl]) es,
             Lookups popl '["s", "i", "r", "v"] Int,
             Observables env '["𝜉"] Int, Observables env '["β", "η", "γ", "ω", "ρ"] Double)
  => Int -> Record popl -> Model env es (Record popl, [Record popl])
hmmSIRSV n = handleWriterM . hmmGen transPriorSIRSV obsPriorSIR transSIRSV obsSIR n