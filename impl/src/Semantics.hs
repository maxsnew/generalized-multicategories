{-# LANGUAGE TemplateHaskell #-}
module Semantics where

import Control.Lens
import Control.Monad.State
import Data.Bifunctor

import Util

-- | equivalent to NEListof Int, but more useful for operations
data DBRef
  = DBCurMod Int
  | DBOutMod DBRef
  deriving (Show, Eq)

type SetNF = DBRef

data EltNF
  = ENFId
  | ENFFunApp DBRef EltNF
  deriving (Show, Eq)

data ScopedSemFun = ScopedSemFun { _scfunDom :: SetNF, _scfunCod :: SetNF, _scfun :: EltNF }
$(makeLenses ''ScopedSemFun)

data SpanNF = SNFSpanApp { _spanSymb :: DBRef, _contraElt :: EltNF, _covarElt :: EltNF }
  deriving (Show, Eq)

data ScopedSemSpan = ScopedSemSpan { _scspContra :: SetNF, _scspCovar :: SetNF, _scspan :: SpanNF }
$(makeLenses ''ScopedSemSpan)

data TransNF
  = TNFId
  | TNFApp DBRef [TransNF]
  deriving (Show, Eq)

type NamedSemTransCtx = ConsStar (String, SetNF, String, SpanNF) (String, SetNF)
type SemTransCtx = ConsStar (SetNF, SpanNF) SetNF

data ScopedSemTrans
  = ScopedSemTrans { _sctransCtx  :: SemTransCtx -- domains
                   , _sctransCod  :: SpanNF      -- codomain
                   , _sctrans     :: TransNF }
$(makeLenses ''ScopedSemTrans)

-- | 
data ScopedVal
  = SemSet SetNF
  | SemFun ScopedSemFun
  | SemSpan ScopedSemSpan
  | SemTrans ScopedSemTrans
-- | SemProof ??
  -- | SemSig -- TODO
  | SemMod ScopedSemMod  -- TODO

data Type
  = TypeSet
  | TypeFun SetNF SetNF
  | TypeSpan SetNF SetNF
  | TypeTrans SemTransCtx SpanNF

substDBRef :: DBRef -> [ScopedVal] -> Either DBRef ScopedVal
substDBRef (DBCurMod n) g = Right $ g !! n
substDBRef (DBOutMod d) g = Left d

typeOf :: ScopedVal -> Type
typeOf (SemSet _) = TypeSet
typeOf (SemFun (ScopedSemFun dom cod _)) = TypeFun dom cod
typeOf (SemSpan (ScopedSemSpan contra covar _)) = TypeSpan contra covar
typeOf (SemTrans (ScopedSemTrans ctx cod _)) = TypeTrans ctx cod
typeOf (SemMod _) = error "NYI: first class modules"

dbVal :: DBRef -> Type -> ScopedVal
dbVal n (TypeSet) = SemSet n
dbVal n (TypeFun dom cod) = SemFun $ ScopedSemFun dom cod (ENFFunApp n ENFId)
dbVal n (TypeSpan contra covar) = SemSpan $ ScopedSemSpan contra covar (SNFSpanApp n ENFId ENFId)
dbVal n (TypeTrans doms cod) = SemTrans $ ScopedSemTrans doms cod (TNFApp n (map (const TNFId) . ctxSpans $ doms))


-- Push a value under a binder
shiftVal :: ScopedVal -> ScopedVal
shiftVal (SemSet db) = SemSet (shiftSet db)
shiftVal (SemFun (ScopedSemFun dom cod fun)) = SemFun (ScopedSemFun (shiftSet dom) (shiftSet cod) (shiftElt fun))
shiftVal (SemSpan (ScopedSemSpan contra covar span)) = SemSpan (ScopedSemSpan (shiftSet contra) (shiftSet covar) (shiftSpan span))
shiftVal (SemTrans (ScopedSemTrans ctx cod f)) = error "NYI: transsss" -- SemSpan (ScopedSemSpan (shiftSet contra) (shiftSet covar) (shiftSpan span))
shiftVal (SemMod (ScopedSemMod sc m)) = error "NYI" -- SemSpan (ScopedSemSpan (shiftSet contra) (shiftSet covar) (shiftSpan span))

subst :: ScopedVal -> [ScopedVal] -> ScopedVal
subst (SemSet s) g = SemSet (substSet s g)
subst (SemFun (ScopedSemFun dom cod f)) g = SemFun (ScopedSemFun (substSet dom g) (substSet cod g) (substElt f g))
subst _ _ = error "NYI: substitution for spans, transformations, modules, signatures"

shiftSet = DBOutMod

substSet :: SetNF -> [ScopedVal] -> SetNF
substSet s g = case substDBRef s g of
  Left r -> r
  Right (SemSet r) -> r

shiftElt ENFId = ENFId
shiftElt (ENFFunApp f t) = (ENFFunApp (DBOutMod f) (shiftElt t))

substElt :: EltNF -> [ScopedVal] -> EltNF
substElt ENFId g = ENFId
substElt (ENFFunApp f t) g = (\x -> unquoteSemFun x (substElt t g)) $ case (substDBRef f g) of
  Left r -> (ENFFunApp r ENFId)
  Right (SemFun (ScopedSemFun _ _ f)) -> f

shiftSpan (SNFSpanApp r contra covar) = SNFSpanApp (DBOutMod r) (shiftElt contra) (shiftElt covar)

namedIndices :: NamedSemTransCtx -> NEList (String, SetNF)
namedIndices = consStartoNE . first (\(x,s,_,_) -> (x,s))

ctxIndices :: SemTransCtx -> NEList SetNF
ctxIndices = consStartoNE . first fst

ctxScopeSpans :: SemTransCtx -> [ScopedSemSpan]
ctxScopeSpans = snd . foldConsStar cons done
  where cons (contra, span) (covar, spans) = (contra, ScopedSemSpan contra covar span :spans)
        done covar = (covar, [])

ctxSpans :: SemTransCtx -> [SpanNF]
ctxSpans = allAs . first snd

ctxUnName :: NamedSemTransCtx -> SemTransCtx
ctxUnName = bimap (\(_,a,_,r) -> (a,r)) snd

boundary :: SemTransCtx -> (SetNF, SetNF)
boundary = firstAndLast . ctxIndices

type SemTransSubst = [TransNF] -> [TransNF]

quoteSemFun :: (EltNF -> EltNF) -> EltNF
quoteSemFun f = f ENFId

unquoteSemFun :: EltNF -> (EltNF -> EltNF)
unquoteSemFun ENFId = id
unquoteSemFun (ENFFunApp f bod) = ENFFunApp f . unquoteSemFun bod

quoteSemSpan :: (EltNF -> EltNF -> SpanNF) -> SpanNF
quoteSemSpan r = r ENFId ENFId

unquoteSpan :: SpanNF -> (EltNF -> EltNF -> SpanNF)
unquoteSpan (SNFSpanApp r contra covar) contrain covarin = SNFSpanApp r (unquoteSemFun contra contrain) (unquoteSemFun covar covarin)

quoteSemTrans :: ([TransNF] -> TransNF) -> TransNF
quoteSemTrans t = t (repeat TNFId)

unquoteSemTrans :: TransNF -> ([TransNF] -> TransNF)
unquoteSemTrans = evalState . unquoteTransComp

pop :: State [a] a
pop = do
  x:xs <- get
  put xs
  return x

unquoteTransComp :: TransNF -> State [TransNF] TransNF
unquoteTransComp TNFId         = pop
unquoteTransComp (TNFApp f ts) = TNFApp f <$> unquoteTransSubstComp ts

unquoteTransSubst :: [TransNF] -> ([TransNF] -> [TransNF])
unquoteTransSubst = evalState . unquoteTransSubstComp

unquoteTransSubstComp :: [TransNF] -> State [TransNF] [TransNF]
unquoteTransSubstComp = traverse unquoteTransComp

data ScopedSemMod = ScopedSemMod ModScope ModNF
type ModScope = ()

type SemMod = [ScopedVal] -> [ScopedVal]

data ModNF
  = ModNFApp  DBRef [ScopedVal]
  | ModNFBase [Type] [(String, ScopedVal)]

