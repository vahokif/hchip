module HChip.ALU (aluOps) where

import Prelude hiding (div, and)
import Control.Applicative
import Control.Lens
import Control.Monad
import Data.Bits
import Data.Int
import Data.Word

import HChip.CPU
import HChip.Machine
import HChip.Util

type AluFunc = Word16 -> Word16 -> Emu Word16

aluFuncs :: [ ( Word8, String, AluFunc )]
aluFuncs =
  [ ( 0x40, "ADD", add )
  , ( 0x50, "SUB", sub )
  , ( 0x60, "AND", and )
  , ( 0x70, "OR",  pureFunc (.|.) )
  , ( 0x80, "XOR", pureFunc xor )
  , ( 0x90, "MUL", mul )
  , ( 0xA0, "DIV", div )
  ]

-- slight hack so we can use it as an operand below
-- maybe it should be canonical
instance Loadable16 Word16 where
  load16 = return

wrap f x y = do
  xv <- load16 x
  yv <- load16 y
  r <- f xv yv
  checkZero r
  checkNegative r
  return r

updateImm f rx y = wrap f rx y >>= save16 rx
updateReg f rx ry = wrap f rx ry >>= save16 rx
resultRegs f rx ry rz = wrap f rx ry >>= save16 rz

genModes :: Word8 -> String -> AluFunc -> [ ( Word8, Instruction ) ]
genModes o m f =
  [ i o (m ++ "I") (r x // imm) (updateImm f)
  , i (o + 1) m (r x // r y) (updateReg f)
  , i (o + 2) m (r x // r y // r z) (resultRegs f)
  ]

sh r = pureFunc (\x n -> shift x (fromIntegral (n .&. 0xf) * if r then (-1) else 1))

genShifts oo m f = 
  [ i (0xB0 + oo) m (r x // imm) (updateImm f)
  , i (0xB4 + oo) m (r x // r y) (updateReg f)
  ]

aluOps = (do
  ( o, m, f ) <- aluFuncs
  genModes o m f) ++
  [ i 0x53 "CMPI" (r x // imm) $ \rx v' -> void (wrap sub rx v')
  , i 0x54 "CMP"  (r x // r y) $ \rx ry -> void (wrap sub rx ry)

  , i 0x63 "TSTI" (r x // imm) $ \rx v' -> void (wrap and rx v')
  , i 0x64 "TST"  (r x // r y) $ \rx ry -> void (wrap and rx ry)

  , i 0xB0 "SHL"  (r x // imm) (updateImm (sh False))
  , i 0xB1 "SHR"  (r x // imm) (updateImm (sh True))
  , i 0xB2 "SAR"  (r x // imm) (updateImm (signed (sh True)))
  , i 0xB3 "SHL"  (r x // r y) (updateReg (sh False))
  , i 0xB4 "SHR"  (r x // r y) (updateReg (sh True))
  , i 0xB5 "SAR"  (r x // r y) (updateReg (signed (sh True)))
  ]

-- UTILITIES

expand :: Int16 -> Int32
expand = fromIntegral

expand' :: Word16 -> Word32
expand' = fromIntegral

compress :: Int32 -> Int16
compress = fromIntegral

bits x = [ if testBit x n then 1 else 0 | n <- [31,30..0]]

pos :: (Num a, Ord a) => a -> Bool
pos = (>=0)

eqv :: Bool -> Bool -> Bool
eqv = (==)

neqv :: Bool -> Bool -> Bool
neqv = (/=)

signed f x x' = unsign <$> f (sign x) (sign x')
pureFunc f x x' = return (f x x')

checkZero x = zero .= (x == 0)
checkNegative x = negative .= (sign x < 0)

-- FUNCTIONS

-- undefined behavior on divide by zero
div :: AluFunc
div = signed $ \x y -> if y == 0 then return 0 else do
  let (q, r) = x `quotRem` y
  carry .= (r /= 0)
  return q

mul :: AluFunc
mul x y = do
  let r = expand (sign x) * expand (sign y)
  let ur = expand' x * expand' y
  carry .= (ur > expand' maxBound)
  return $ unsign $ compress r

add :: AluFunc
add = signed $ \x y -> do
  let r = x + y
  carry .= (unsign r < unsign x)
  overflow .= (pos x == pos y && pos x /= pos r)
  return r

sub :: AluFunc
sub = signed $ \x y -> do
  let r = x - y
  carry .= (unsign r > unsign x)
  overflow .= (pos x /= pos y && pos y == pos r)
  return r

and :: AluFunc
and = pureFunc (.&.)