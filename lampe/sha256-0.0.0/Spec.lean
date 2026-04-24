-- Specification for SHA-256 variable-length hashing
--
-- This module defines the mathematical correctness criterion for `sha256_var`.
-- The formal proof obligation is to show that the Lampe translation of
-- `sha256_var` in Extracted/Sha256.lean returns the SHA-256 digest of the
-- first `message_size` bytes of `msg`.

import «sha256-0.0.0».Extracted

open Lampe

namespace Sha256.Spec

-- ============================================================
-- 1.  Types and constants
-- ============================================================

/-- The 8-word SHA-256 intermediate hash state. -/
abbrev State := List.Vector (U 32) 8

/-- A 16-word (512-bit) SHA-256 message block. -/
abbrev MsgBlock := List.Vector (U 32) 16

/-- The 32-byte SHA-256 digest. -/
abbrev Hash := List.Vector (U 8) 32

/-- SHA-256 initial hash values H₀: the first 32 bits of the fractional parts
    of the square roots of the first 8 prime numbers. -/
def initialState : State :=
  ⟨[1779033703, 3144134277, 1013904242, 2773480762,
    1359893119, 2600822924, 528734635, 1541459225], rfl⟩

/-- Block size in bytes: 64 = 512 bits. -/
def BLOCK_SIZE : ℕ := 64

/-- Size of one u32 word in bytes. -/
def INT_SIZE : ℕ := 4

/-- Byte offset into a 64-byte block at which the 8-byte length field begins. -/
def MSG_SIZE_PTR : ℕ := 56

/-- Word index (in the 16-word block) of the start of the 8-byte length field:
    56 / 4 = 14. -/
def INT_SIZE_PTR : ℕ := 14

-- ============================================================
-- 2.  Abstract sha256Compression primitive
-- ============================================================

/-- Abstract SHA-256 compression function: maps a (message-block, state) pair
    to a new state according to the SHA-256 round function.
    This is the opaque model of the `#_sha256Compression` Noir/Lampe builtin. -/
noncomputable opaque sha256CompressionFn (block : MsgBlock) (state : State) : State

/-- `Sha256CompressionSpec p Γ` asserts that the `sha256Compression` Lampe
    builtin behaves as `sha256CompressionFn` in environment `Γ`. -/
abbrev Sha256CompressionSpec (p : Prime) (Γ : Env) : Prop :=
  ∀ (block : MsgBlock) (state : State),
    STHoare p Γ ⟦⟧
      (.callBuiltin [.array (.u 32) 16, .array (.u 32) 8] (.array (.u 32) 8)
        .sha256Compression h![block, state])
      (fun r => r = sha256CompressionFn block state)

-- ============================================================
-- 3.  Reference implementation helpers
-- ============================================================

section

/-- Construct a `List.Vector α n` from a function `Fin n → α`. -/
private def vecOfFn {α : Type*} {n : ℕ} (f : Fin n → α) : List.Vector α n :=
  ⟨List.ofFn f, by simp⟩

/-- A `List.Vector` of `n` copies of `a`. -/
private def vecReplicate {α : Type*} (n : ℕ) (a : α) : List.Vector α n :=
  ⟨List.replicate n a, by simp⟩

/-- Build one 16-word message block from `bytes[msg_start .. msg_start + 64)`,
    treating bytes at index ≥ `message_size` as 0.
    Word `i` packs `bytes[msg_start + 4*i .. msg_start + 4*i + 4)` big-endian. -/
def buildMsgBlockRef (bytes : List (U 8)) (message_size msg_start : ℕ) : MsgBlock :=
  vecOfFn (fun (i : Fin 16) =>
    let off  := msg_start + INT_SIZE * i.val
    let byte := fun j => if off + j < message_size then (bytes.getD (off + j) 0).toNat else 0
    BitVec.ofNat 32 (byte 0 * 2^24 + byte 1 * 2^16 + byte 2 * 2^8 + byte 3))

/-- Process all complete 64-byte blocks in `bytes[0..message_size)` by
    repeatedly applying `sha256CompressionFn`, starting from `h₀`.
    Returns the resulting intermediate state and the first partial (un-compressed)
    message block. -/
def processFullBlocksWith
    (compress : MsgBlock → State → State)
    (bytes : List (U 8)) (message_size : ℕ) (h₀ : State) : State × MsgBlock :=
  let num_full_blocks := message_size / BLOCK_SIZE
  let h :=
    (List.range num_full_blocks).foldl
      (fun h i =>
        compress (buildMsgBlockRef bytes message_size (BLOCK_SIZE * i)) h)
      h₀
  let msg_byte_ptr := message_size % BLOCK_SIZE
  let partialBlock :=
    if msg_byte_ptr ≠ 0 then
      buildMsgBlockRef bytes message_size (BLOCK_SIZE * num_full_blocks)
    else
      vecReplicate 16 0
  (h, partialBlock)

noncomputable def processFullBlocksRef :=
  processFullBlocksWith sha256CompressionFn

/-- The value added to a u32 word to set the 0x80 bit at byte position
    `msg_byte_ptr % 4` within that word.  Mirrors `PADDING_BIT_TABLE`. -/
def paddingWordNat (msg_byte_ptr : ℕ) : ℕ :=
  match msg_byte_ptr % 4 with
  | 0 => 0x80000000  -- 0x80 in most-significant byte
  | 1 => 0x00800000
  | 2 => 0x00008000
  | _ => 0x00000080  -- 0x80 in least-significant byte

/-- Insert the 0x80 padding byte at byte position `msg_byte_ptr` in `block`,
    then optionally flush and zero the block if there is insufficient room for
    the 8-byte length field (`msg_byte_ptr ≥ 56`).
    Precondition: `msg_byte_ptr < 64`. -/
def addPaddingAndCompressWith
    (compress : MsgBlock → State → State)
    (block : MsgBlock) (msg_byte_ptr : ℕ) (hb : msg_byte_ptr < BLOCK_SIZE) (h : State)
    : State × MsgBlock :=
  have hw : msg_byte_ptr / 4 < 16 := by simp only [BLOCK_SIZE] at hb; omega
  let word_idx : Fin 16 := ⟨msg_byte_ptr / INT_SIZE, hw⟩
  let block' := block.set word_idx
    (block.get word_idx + BitVec.ofNat 32 (paddingWordNat msg_byte_ptr))
  if msg_byte_ptr ≥ MSG_SIZE_PTR then
    (compress block' h, vecReplicate 16 0)
  else
    (h, block')

noncomputable def addPaddingAndCompressRef :=
  addPaddingAndCompressWith sha256CompressionFn

/-- Encode `8 * message_size` (bit-length of the message) as two u32 limbs.
    Returns `(lo, hi)` such that `lo + hi * 2^32 = 8 * message_size`. -/
def encodeLenRef (message_size : ℕ) : ℕ × ℕ :=
  let bits := 8 * message_size
  (bits % 2 ^ 32, bits / 2 ^ 32)

/-- Write the 64-bit big-endian bit-length into the last two words of `block`:
    word 14 ← hi, word 15 ← lo, where `hi * 2^32 + lo = 8 * message_size`. -/
def attachLenRef (block : MsgBlock) (message_size : ℕ) : MsgBlock :=
  let (lo, hi) := encodeLenRef message_size
  (block.set ⟨14, by norm_num⟩ (BitVec.ofNat 32 hi)).set ⟨15, by norm_num⟩ (BitVec.ofNat 32 lo)

/-- Serialise the 8-word state to a 32-byte hash by unpacking each word in
    big-endian byte order: byte `4j + k` = bits `[32-8k-8 .. 32-8k)` of word `j`. -/
def stateToHashRef (state : State) : Hash :=
  vecOfFn (fun (i : Fin 32) =>
    let word  := (state.get ⟨i.val / 4, by omega⟩).toNat
    let shift := 8 * (3 - i.val % 4)
    BitVec.ofNat 8 ((word >>> shift) % 256))

/-- Finalize the hash after all full blocks have been processed:
    1. Append the 0x80 padding byte; flush the block if necessary.
    2. Write the big-endian 64-bit message bit-length into words 14–15.
    3. Compress the final padded block.
    4. Serialise the resulting 8-word state to 32 bytes. -/
def finalizeSha256BlocksWith
    (compress : MsgBlock → State → State)
    (message_size : ℕ) (h : State) (block : MsgBlock) : Hash :=
  let msg_byte_ptr := message_size % BLOCK_SIZE
  have hb : msg_byte_ptr < BLOCK_SIZE := Nat.mod_lt _ (by norm_num [BLOCK_SIZE])
  let (h', block') := addPaddingAndCompressWith compress block msg_byte_ptr hb h
  let block'' := attachLenRef block' message_size
  stateToHashRef (compress block'' h')

noncomputable def finalizeSha256BlocksRef :=
  finalizeSha256BlocksWith sha256CompressionFn

end

-- ============================================================
-- 4.  Top-level reference function and specification predicate
-- ============================================================

/-- SHA-256 pipeline parametric over the compression function. -/
def sha256With (compress : MsgBlock → State → State)
    (bytes : List (U 8)) (message_size : ℕ) : Hash :=
  let (h, block) := processFullBlocksWith compress bytes message_size initialState
  finalizeSha256BlocksWith compress message_size h block

/-- Reference SHA-256 computation for `bytes[0..message_size)`. -/
noncomputable def sha256Ref := sha256With sha256CompressionFn

/-- `sha256VarSpec msg message_size` is the SHA-256 digest of the first
    `message_size` bytes of the N-byte array `msg`.
    This is the value that a correct `sha256_var` must return. -/
noncomputable def sha256VarSpec {N : ℕ} (msg : List.Vector (U 8) N) (message_size : ℕ) : Hash :=
  sha256Ref msg.toList message_size

-- ============================================================
-- 5.  Sub-lemmas (each sorry'd; to be proved individually)
-- ============================================================

/-- `build_msg_block` (constrained form) produces the same 16-word block
    as `buildMsgBlockRef`.

    Proof strategy: show that the constraint loop in `build_msg_block` forces
    each `msg_block[i]` to equal the big-endian packing of the four input bytes,
    matching `buildMsgBlockRef`. -/
theorem build_msg_block_spec {p : Prime} {N : U 32}
    (msg         : List.Vector (U 8) N.toNat)
    (message_size : U 32)
    (msg_start   : U 32)
    (h_comp : Sha256CompressionSpec p «sha256-0.0.0».env) :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::build_msg_block».call h![N] h![msg, message_size, msg_start])
      (fun r => r = buildMsgBlockRef msg.toList message_size.toNat msg_start.toNat) := by
  sorry

/-- `process_full_blocks` (constrained form) produces the same intermediate
    state and partial block as `processFullBlocksRef`.

    Proof strategy: the constrained form enumerates all possible `message_size`
    values via a lookup table of precomputed block compressions; show that for
    the actual `message_size`, the selected state equals the sequential fold in
    `processFullBlocksRef`. -/
theorem process_full_blocks_spec {p : Prime} {N : U 32}
    (msg           : List.Vector (U 8) N.toNat)
    (message_size  : U 32)
    (initial_state : State)
    (h_comp : Sha256CompressionSpec p «sha256-0.0.0».env) :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::process_full_blocks».call h![N]
        h![msg, message_size, initial_state])
      (fun r =>
        let (h, block) := processFullBlocksRef msg.toList message_size.toNat initial_state
        r = (h, block, ())) := by
  sorry

/-- `attach_len_to_msg_block` writes the encoded bit-length into words 14 and 15.

    Proof strategy: the unconstrained `encode_len` produces a witness `(lo, hi)`;
    the assertion `8 * message_size = lo + hi * 2^32` pins the values uniquely
    (since both limbs fit in u32), so the result equals `attachLenRef`. -/
theorem attach_len_to_msg_block_spec {p : Prime}
    (block        : MsgBlock)
    (message_size : U 32) :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::attach_len_to_msg_block».call h![] h![block, message_size])
      (fun r => r = attachLenRef block message_size.toNat) := by
  sorry

/-- `hash_final_block` compresses `block` against `state` via `sha256Compression`,
    then unpacks the resulting 8-word state into 32 bytes big-endian. -/
theorem hash_final_block_spec {p : Prime}
    (block : MsgBlock)
    (state : State)
    (h_comp : Sha256CompressionSpec p «sha256-0.0.0».env) :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::hash_final_block».call h![] h![block, state])
      (fun r => r = stateToHashRef (sha256CompressionFn block state)) := by
  sorry

/-- `add_padding_byte_and_compress_if_needed` inserts the 0x80 padding byte at
    `msg_byte_ptr` and conditionally flushes the block, matching
    `addPaddingAndCompressRef`. -/
theorem add_padding_and_compress_spec {p : Prime}
    (block        : MsgBlock)
    (msg_byte_ptr : U 32)
    (h_bnd        : msg_byte_ptr.toNat < BLOCK_SIZE)
    (state        : State)
    (h_comp : Sha256CompressionSpec p «sha256-0.0.0».env) :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::add_padding_byte_and_compress_if_needed».call h![]
        h![block, msg_byte_ptr, state])
      (fun r =>
        let (h', block') := addPaddingAndCompressRef block msg_byte_ptr.toNat h_bnd state
        r = (h', block', ())) := by
  sorry

/-- `finalize_sha256_blocks` pads the partial block, writes the length, performs
    the final compression, and serialises the state — matching
    `finalizeSha256BlocksRef`.

    Proof strategy: compose `add_padding_and_compress_spec`,
    `attach_len_to_msg_block_spec`, `hash_final_block_spec`. -/
theorem finalize_sha256_blocks_spec {p : Prime}
    (message_size : U 32)
    (h            : State)
    (block        : MsgBlock)
    (h_comp : Sha256CompressionSpec p «sha256-0.0.0».env) :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::finalize_sha256_blocks».call h![] h![message_size, h, block])
      (fun r => r = finalizeSha256BlocksRef message_size.toNat h block) := by
  sorry

-- ============================================================
-- 6.  Main correctness theorem
-- ============================================================

/-- `sha256_var` is correct: given a byte array `msg` of capacity `N` and a
    runtime `message_size ≤ N`, it returns the SHA-256 digest of the first
    `message_size` bytes of `msg`.

    The proof proceeds by:
    1. Applying `process_full_blocks_spec` to relate the constrained block
       loop to `processFullBlocksRef`.
    2. Applying `finalize_sha256_blocks_spec` to relate the padding and final
       compression to `finalizeSha256BlocksRef`.
    3. Unfolding `sha256VarSpec` and `sha256Ref` to conclude.

    Prerequisite:
    · `h_comp` — the `sha256Compression` Lampe builtin behaves as
      `sha256CompressionFn`. -/
theorem sha256_var_correct {p : Prime} {N : U 32}
    (msg          : List.Vector (U 8) N.toNat)
    (message_size : U 32)
    (h_bound      : message_size.toNat ≤ N.toNat)
    (h_comp       : Sha256CompressionSpec p «sha256-0.0.0».env) :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::sha256_var».call h![N] h![msg, message_size])
      (fun result => result = sha256VarSpec msg message_size.toNat) := by
  sorry

-- ============================================================
-- 7.  Checked tests for computable helpers
-- ============================================================

section Tests

-- ---- paddingWordNat ----

-- 0x80 lands in the correct byte position within the u32 word.
#guard paddingWordNat 0 == 0x80000000   -- most-significant byte
#guard paddingWordNat 1 == 0x00800000
#guard paddingWordNat 2 == 0x00008000
#guard paddingWordNat 3 == 0x00000080   -- least-significant byte

-- ---- encodeLenRef ----

-- 1 byte of message → 8 bits; fits in lo, hi = 0.
#guard encodeLenRef 0 == (0, 0)
#guard encodeLenRef 1 == (8, 0)

-- ---- buildMsgBlockRef ----

-- Noir test_build_msg_block_start_0: 22-byte input "from:runner.leagues.0", block at byte 0.
private def bytes22 : List (U 8) :=
  [102, 114, 111, 109, 58, 114, 117, 110,
   110, 105, 101, 114, 46, 108, 101, 97,
   103, 117, 101, 115, 46, 48]

-- word 0 = 0x66726F6D ("from"), word 1 = 0x3A72756E (":run"),
-- word 5 = 0x2E300000 (".0\0\0"), word 6 = 0 (past message_size)
example : (buildMsgBlockRef bytes22 22 0).get ⟨0, by norm_num⟩ = (1718775661 : U 32) := by
  native_decide
example : (buildMsgBlockRef bytes22 22 0).get ⟨1, by norm_num⟩ = (980579694 : U 32) := by
  native_decide
example : (buildMsgBlockRef bytes22 22 0).get ⟨5, by norm_num⟩ = (774897664 : U 32) := by
  native_decide
example : (buildMsgBlockRef bytes22 22 0).get ⟨6, by norm_num⟩ = (0 : U 32) := by
  native_decide

-- Noir test_build_msg_block_start_1: 68-byte input, block starting at byte 64.
private def bytes68 : List (U 8) :=
  [102, 114, 111, 109, 58, 114, 117, 110, 110, 105, 101, 114, 46, 108, 101, 97,
   103, 117, 101, 115, 46, 48, 106, 64, 105, 99, 108, 111, 117, 100, 46, 99,
   111, 109, 13, 10, 99, 111, 110, 116, 101, 110, 116, 45, 116, 121, 112, 101,
   58, 116, 101, 120, 116, 47, 112, 108, 97, 105, 110, 59, 32, 99, 104, 97,
   114, 115, 101, 116]

-- word 0 = 0x72736574 ("rset"), word 1 = 0 (bytes 68-71 are past message_size)
example : (buildMsgBlockRef bytes68 68 64).get ⟨0, by norm_num⟩ = (1920165236 : U 32) := by
  native_decide
example : (buildMsgBlockRef bytes68 68 64).get ⟨1, by norm_num⟩ = (0 : U 32) := by
  native_decide

-- ---- attachLenRef ----

-- Noir test_attach_len_to_msg_block: message_size = 1 → bit-length = 8.
-- Words 14–15 are replaced by hi=0 and lo=8; words 0–13 are preserved.
private def blockBefore : MsgBlock :=
  ⟨[2152555847, 1397309779, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1849316213, 1651139939], rfl⟩

example : (attachLenRef blockBefore 1).get ⟨14, by norm_num⟩ = (0 : U 32) := by native_decide
example : (attachLenRef blockBefore 1).get ⟨15, by norm_num⟩ = (8 : U 32) := by native_decide

-- Words 0–13 are unchanged after attachLenRef.
example : (attachLenRef blockBefore 1).get ⟨0, by norm_num⟩ =
          blockBefore.get ⟨0, by norm_num⟩ := by native_decide

-- ---- stateToHashRef ----

-- FIPS 180-4 §5.3.3: initial hash values H₀ serialised as 32 big-endian bytes.
-- H₀[0] = 0x6A09E667 → [106, 9, 230, 103]; H₀[1] = 0xBB67AE85 → [187, 103, 174, 133]; …
example : stateToHashRef initialState =
    ⟨[106,   9, 230, 103,
      187, 103, 174, 133,
       60, 110, 243, 114,
      165,  79, 245,  58,
       81,  14,  82, 127,
      155,   5, 104, 140,
       31, 131, 217, 171,
       91, 224, 205,  25], rfl⟩ := by native_decide

end Tests

-- ============================================================
-- 8.  Computable reference for sha256CompressionFn
-- ============================================================

section Sha256Round

-- FIPS 180-4 §4.1.2: functions on 32-bit words.
private abbrev W := U 32
private def rotr (n : Nat) (x : W) : W := (x >>> n) ||| (x <<< (32 - n))
private def ch   (x y z : W) : W := (x &&& y) ^^^ (~~~x &&& z)
private def maj  (x y z : W) : W := (x &&& y) ^^^ (x &&& z) ^^^ (y &&& z)
private def bigSigma0  (x : W) : W := rotr 2  x ^^^ rotr 13 x ^^^ rotr 22 x
private def bigSigma1  (x : W) : W := rotr 6  x ^^^ rotr 11 x ^^^ rotr 25 x
private def smallSigma0 (x : W) : W := rotr 7  x ^^^ rotr 18 x ^^^ (x >>> 3)
private def smallSigma1 (x : W) : W := rotr 17 x ^^^ rotr 19 x ^^^ (x >>> 10)

-- FIPS 180-4 §4.2.2: SHA-256 round constants K[0..63].
private def kConst : Array W :=
  #[0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]

/-- SHA-256 compression function (FIPS 180-4 §6.2.2).
    Computable counterpart to the opaque `sha256CompressionFn`. -/
def sha256CompressionImpl (block : MsgBlock) (state : State) : State :=
  -- Step 1: extend the 16-word block into a 64-word message schedule.
  let w : Array W :=
    (List.range 48).foldl
      (fun w i =>
        let t := i + 16
        w.push (smallSigma1 w[t - 2]! + w[t - 7]! + smallSigma0 w[t - 15]! + w[t - 16]!))
      (Array.mk block.toList)
  -- Steps 2–3: initialise working variables and run 64 rounds.
  let s : Array W := (List.range 64).foldl
      (fun s t =>
        let a := s[0]!; let b := s[1]!; let c := s[2]!; let d := s[3]!
        let e := s[4]!; let f := s[5]!; let g := s[6]!; let h := s[7]!
        let t1 := h + bigSigma1 e + ch e f g + kConst[t]! + w[t]!
        let t2 := bigSigma0 a + maj a b c
        #[t1 + t2, a, b, c, d + t1, e, f, g])
      (Array.mk state.toList)
  -- Step 4: add compressed chunk to current hash value.
  vecOfFn fun i => state.get i + s[i.val]!

-- FIPS 180-4 §B.1: SHA-256 of "abc" fits in one block.
-- Padded: "abc" + 0x80 byte, 13 zero words, 64-bit big-endian bit-length 24.
private def abcBlock : MsgBlock :=
  ⟨[0x61626380, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x18], rfl⟩

example : stateToHashRef (sha256CompressionImpl abcBlock initialState) =
    ⟨[0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
      0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
      0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
      0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad], rfl⟩ := by native_decide

/-- Computable end-to-end SHA-256: `sha256With` instantiated with the concrete
    compression function instead of the opaque builtin. -/
def sha256VarImpl := sha256With sha256CompressionImpl

-- ---- Known test vectors ----

-- Empty message (NIST / Noir `empty_sha256` test).
example : sha256VarImpl [] 0 =
    ⟨[0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14,
      0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f, 0xb9, 0x24,
      0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c,
      0xa4, 0x95, 0x99, 0x1b, 0x78, 0x52, 0xb8, 0x55], rfl⟩ := by native_decide

-- Single byte 0xBD (Noir `smoke_test`).
example : sha256VarImpl [0xBD] 1 =
    ⟨[0x68, 0x32, 0x57, 0x20, 0xaa, 0xbd, 0x7c, 0x82,
      0xf3, 0x0f, 0x55, 0x4b, 0x31, 0x3d, 0x05, 0x70,
      0xc9, 0x5a, 0xcc, 0xbb, 0x7d, 0xc4, 0xb5, 0xaa,
      0xe1, 0x12, 0x04, 0xc0, 0x8f, 0xfe, 0x73, 0x2b], rfl⟩ := by native_decide

-- FIPS 180-4 §B.1: SHA-256("abc") — one block.
example : sha256VarImpl [0x61, 0x62, 0x63] 3 =
    ⟨[0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
      0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
      0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
      0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad], rfl⟩ := by native_decide

-- FIPS 180-4 §B.2: SHA-256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq").
-- 56 bytes: the 0x80 byte falls at word 14, forcing a block flush before the length word.
private def b2msg : List (U 8) :=
  [97, 98, 99, 100, 98, 99, 100, 101, 99, 100, 101, 102, 100, 101, 102, 103,
   101, 102, 103, 104, 102, 103, 104, 105, 103, 104, 105, 106, 104, 105, 106, 107,
   105, 106, 107, 108, 106, 107, 108, 109, 107, 108, 109, 110, 108, 109, 110, 111,
   109, 110, 111, 112, 110, 111, 112, 113]

example : sha256VarImpl b2msg 56 =
    ⟨[0x24, 0x8d, 0x6a, 0x61, 0xd2, 0x06, 0x38, 0xb8,
      0xe5, 0xc0, 0x26, 0x93, 0x0c, 0x3e, 0x60, 0x39,
      0xa3, 0x3c, 0xe4, 0x59, 0x64, 0xff, 0x21, 0x67,
      0xf6, 0xec, 0xed, 0xd4, 0x19, 0xdb, 0x06, 0xc1], rfl⟩ := by native_decide

end Sha256Round

end Sha256.Spec
