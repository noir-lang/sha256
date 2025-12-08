use std::hash::sha256_compression;
use std::runtime::is_unconstrained;

use constants::{
    BLOCK_BYTE_PTR, BLOCK_SIZE, HASH, INITIAL_STATE, INT_BLOCK_SIZE, INT_SIZE, INT_SIZE_PTR,
    MSG_BLOCK, MSG_SIZE_PTR, STATE, TWO_POW_16, TWO_POW_24, TWO_POW_32, TWO_POW_8,
};

pub(crate) mod constants;
mod tests;
mod oracle_tests;

// Implementation of SHA-256 mapping a byte array of variable length to
// 32 bytes.

// Deprecated in favour of `sha256_var`
// docs:start:sha256
pub fn sha256<let N: u32>(input: [u8; N]) -> HASH
// docs:end:sha256
{
    digest(input)
}

// SHA-256 hash function
#[no_predicates]
pub fn digest<let N: u32>(msg: [u8; N]) -> HASH {
    sha256_var(msg, N)
}

// Variable size SHA-256 hash
pub fn sha256_var<let N: u32>(msg: [u8; N], message_size: u32) -> HASH {
    assert(message_size <= N);

    if std::runtime::is_unconstrained() {
        // Safety: SHA256 is running as an unconstrained function.
        unsafe {
            __sha256_var(msg, message_size)
        }
    } else {
        let (h, msg_block) = process_full_blocks(msg, message_size, INITIAL_STATE);

        finalize_sha256_blocks(message_size, h, msg_block)
    }
}

pub(crate) unconstrained fn __sha_var<let N: u32>(
    msg: [u8; N],
    message_size: u32,
    initial_state: STATE,
) -> HASH {
    let num_full_blocks = message_size / BLOCK_SIZE;
    // Intermediate hash, starting with the canonical initial value
    let mut h: STATE = initial_state;
    // Pointer into msg_block on a 64 byte scale
    for i in 0..num_full_blocks {
        let msg_block = build_msg_block(msg, message_size, BLOCK_SIZE * i);
        h = sha256_compression(msg_block, h);
    }

    // Handle setup of the final msg block.
    // This case is only hit if the msg is less than the block size,
    // or our message cannot be evenly split into blocks.

    finalize_last_sha256_block(h, message_size, msg)
}

// Helper function to finalize the message block with padding and length
pub(crate) unconstrained fn finalize_last_sha256_block<let N: u32>(
    mut h: STATE,
    message_size: u32,
    msg: [u8; N],
) -> HASH {
    let msg_byte_ptr = message_size % BLOCK_SIZE;

    // We now build the final un-filled block.
    let msg_block: MSG_BLOCK = if msg_byte_ptr != 0 {
        let num_full_blocks = message_size / BLOCK_SIZE;
        let msg_start = BLOCK_SIZE * num_full_blocks;
        build_msg_block(msg, message_size, msg_start)
    } else {
        // If the message size is a multiple of the block size (i.e. `msg_byte_ptr == 0`) then this block will be empty,
        // so we short-circuit in this case.
        [0; 16]
    };

    // Once built, we need to add the necessary padding bytes and encoded length
    let (h, mut msg_block) = add_padding_byte_and_compress_if_needed(msg_block, msg_byte_ptr, h);
    msg_block = attach_len_to_msg_block(msg_block, message_size);

    hash_final_block(msg_block, h)
}

// Variable size SHA-256 hash
unconstrained fn __sha256_var<let N: u32>(msg: [u8; N], message_size: u32) -> HASH {
    __sha_var(msg, message_size, INITIAL_STATE)
}

pub(crate) fn process_full_blocks<let N: u32>(
    msg: [u8; N],
    message_size: u32,
    h: STATE,
) -> (STATE, MSG_BLOCK) {
    let num_blocks = N / BLOCK_SIZE;

    // We store the intermediate hash states and message blocks in these two arrays which allows us to select the correct state
    // for the given message size with a lookup.
    //
    // These can be reasoned about as followed:
    // Consider a message with an unknown number of bytes, `msg_size. It can be seen that this will have `msg_size / BLOCK_SIZE` full blocks.
    // - `states[i]` should then be the state after processing the first `i` blocks.
    // - `blocks[i]` should then be the next message block after processing the first `i` blocks.
    // blocks[first_partially_filled_block_index] is the last block that is partially filled or all 0 if the message is a multiple of the block size.
    //
    // In other words:
    //
    // blocks = [block 1, block 2, ..., block N / BLOCK_SIZE, block N / BLOCK_SIZE + 1]
    // states = [INITIAL_STATE, state after block 1, state after block 2, ..., state after block N / BLOCK_SIZE]
    //
    // We place the initial state in `states[0]` as in the case where the `message_size < BLOCK_SIZE` then there are no full blocks to process and no compressions should occur.
    let mut blocks: [MSG_BLOCK; N / BLOCK_SIZE + 1] = std::mem::zeroed();
    let mut states: [STATE; N / BLOCK_SIZE + 1] = [h; N / BLOCK_SIZE + 1];

    // Optimization for small messages. If the largest possible message is smaller than a block then we know that the first block is partially filled
    // no matter the value of `message_size`.
    //
    // Note that the condition `N >= BLOCK_SIZE` is known during monomorphization so this has no runtime cost.
    let first_partially_filled_block_index = if N >= BLOCK_SIZE {
        message_size / BLOCK_SIZE
    } else {
        0
    };

    for i in 0..num_blocks {
        let msg_start = BLOCK_SIZE * i;
        let new_msg_block = build_msg_block(msg, message_size, msg_start);

        blocks[i] = new_msg_block;
        states[i + 1] = sha256_compression(new_msg_block, states[i]);
    }
    // If message_size/BLOCK_SIZE == N/BLOCK_SIZE, and there is a remainder, we need to process the last block.
    if N % BLOCK_SIZE != 0 {
        let new_msg_block = build_msg_block(msg, message_size, BLOCK_SIZE * num_blocks);

        blocks[num_blocks] = new_msg_block;
    }

    (states[first_partially_filled_block_index], blocks[first_partially_filled_block_index])
}

// Take `BLOCK_SIZE` number of bytes from `msg` starting at `msg_start` and pack them into a `MSG_BLOCK`.
pub(crate) unconstrained fn build_msg_block_helper<let N: u32>(
    msg: [u8; N],
    message_size: u32,
    msg_start: u32,
) -> MSG_BLOCK {
    let mut msg_block: MSG_BLOCK = [0; INT_BLOCK_SIZE];

    // We insert `BLOCK_SIZE` bytes (or up to the end of the message)
    let block_input = if message_size < msg_start {
        // This function is sometimes called with `msg_start` past the end of the message.
        // In this case we return an empty block and zero pointer to signal that the result should be ignored.
        0
    } else if message_size < msg_start + BLOCK_SIZE {
        message_size - msg_start
    } else {
        BLOCK_SIZE
    };

    // Figure out the number of items in the int array that we have to pack.
    // e.g. if the input is [0,1,2,3,4,5] then we need to pack it as 2 items: [0123, 4500]
    let int_input = (block_input + INT_SIZE - 1) / INT_SIZE;

    for i in 0..int_input {
        let mut msg_item: u32 = 0;
        // Always construct the integer as 4 bytes, even if it means going beyond the input.
        for j in 0..INT_SIZE {
            let k = i * INT_SIZE + j;
            let msg_byte = if k < block_input {
                msg[msg_start + k]
            } else {
                0
            };
            msg_item = (msg_item << 8) + msg_byte as u32;
        }
        msg_block[i] = msg_item;
    }

    // Returning the index as if it was a 64 byte array.
    // We have to project it down to 16 items and bit shifting to get a byte back if we need it.
    msg_block
}

// Build a message block from the input message starting at `msg_start`.
//
// If `message_size` is less than `msg_start` then this is called with the old non-empty block;
// in that case we can skip verification, ie. no need to check that everything is zero.
fn build_msg_block<let N: u32>(msg: [u8; N], message_size: u32, msg_start: u32) -> MSG_BLOCK {
    let msg_block =
        // Safety: We constrain the block below by reconstructing each `u32` word from the input bytes.
        unsafe { build_msg_block_helper(msg, message_size, msg_start) };

    if !is_unconstrained() {
        let mut msg_end = msg_start + BLOCK_SIZE;

        let max_read_index = std::cmp::min(message_size, msg_end);

        // Reconstructed packed item
        let mut msg_item: Field = 0;

        // Inclusive at the end so that we can compare the last item.
        for k in msg_start..=msg_end {
            if (k != msg_start) & (k % INT_SIZE == 0) {
                // If we consumed some input we can compare against the block.
                let msg_block_index = (k - msg_start) / INT_SIZE - 1;
                assert_eq(msg_block[msg_block_index] as Field, msg_item);

                msg_item = 0;
            }

            // If we have input to consume, add it at the rightmost position.
            let msg_byte = if k < max_read_index { msg[k] } else { 0 };
            msg_item = msg_item * (TWO_POW_8 as Field) + msg_byte as Field;
        }
    }
    msg_block
}

// Set the rightmost `zeros` number of bytes to 0.
#[inline_always]
fn set_item_zeros(item: u32, zeros: u32) -> u32 {
    lshift8(rshift8(item, zeros), zeros)
}

// Replace one byte in the item with a value, and set everything after it to zero.
fn set_item_byte_then_zeros(msg_item: u32, msg_byte_ptr: BLOCK_BYTE_PTR, msg_byte: u8) -> u32 {
    let zeros = INT_SIZE - msg_byte_ptr % INT_SIZE;
    let zeroed_item = set_item_zeros(msg_item, zeros);
    let new_item = byte_into_item(msg_byte, msg_byte_ptr);
    zeroed_item + new_item
}

// Project a byte into a position in a field based on the overall block pointer.
// For example putting 1 into pointer 5 would be 100, because overall we would
// have [____, 0100] with indexes [0123,4567].
#[inline_always]
fn byte_into_item(msg_byte: u8, msg_byte_ptr: BLOCK_BYTE_PTR) -> u32 {
    let mut msg_item = msg_byte as u32;
    // How many times do we have to shift to the left to get to the position we want?
    let max_shifts = INT_SIZE - 1;
    let shifts = max_shifts - msg_byte_ptr % INT_SIZE;
    lshift8(msg_item, shifts)
}

global BIT_SHIFT_TABLE: [u32; 4] = [1, TWO_POW_8, TWO_POW_16, TWO_POW_24];

// Shift by 8 bits to the left between 0 and 4 times.
// Checks `is_unconstrained()` to just use a bitshift if we're running in an unconstrained context,
// otherwise multiplies by 256.
#[inline_always]
fn lshift8(item: u32, shifts: u32) -> u32 {
    if is_unconstrained() {
        // Brillig wouldn't shift 0<<4 without overflow.
        if shifts >= 4 {
            0
        } else {
            item << (8 * shifts)
        }
    } else {
        if shifts == 4 {
            0
        } else {
            item * BIT_SHIFT_TABLE[shifts]
        }
    }
}

// Shift by 8 bits to the right between 0 and 4 times.
// Checks `is_unconstrained()` to just use a bitshift if we're running in an unconstrained context,
// otherwise divides by 256.
#[inline_always]
fn rshift8(item: u32, shifts: u32) -> u32 {
    if is_unconstrained() {
        if shifts >= 4 {
            0
        } else {
            item >> (8 * shifts)
        }
    } else {
        if shifts == 4 {
            0
        } else {
            item / BIT_SHIFT_TABLE[shifts]
        }
    }
}

// Encode `8 * message_size` into two `u32` limbs.
unconstrained fn encode_len(message_size: u32) -> (u32, u32) {
    let len = 8 * message_size as u64;
    let lo = len & 0xFFFFFFFF;
    let hi = (len >> 32) & 0xFFFFFFFF;
    (lo as u32, hi as u32)
}

// Write the length into the last 8 bytes of the block.
fn attach_len_to_msg_block(mut msg_block: MSG_BLOCK, message_size: u32) -> MSG_BLOCK {
    // Safety: We assert the correctness of the decomposition below.
    // 2 `u32` limbs cannot overflow the field modulus so performing the check as `Field`s is safe.
    let (lo, hi) = unsafe { encode_len(message_size) };
    assert_eq(8 * (message_size as Field), lo as Field + hi as Field * TWO_POW_32);

    msg_block[INT_SIZE_PTR] = hi;
    msg_block[INT_SIZE_PTR + 1] = lo;
    msg_block
}

// Perform the final compression, then transform the `STATE` into `HASH`.
fn hash_final_block(msg_block: MSG_BLOCK, mut state: STATE) -> HASH {
    // Hash final padded block
    state = sha256_compression(msg_block, state);

    // Return final hash as byte array
    let mut out_h: HASH = [0; 32]; // Digest as sequence of bytes
    for j in 0..8 {
        let h_bytes: [u8; 4] = (state[j] as Field).to_be_bytes();
        for k in 0..4 {
            out_h[4 * j + k] = h_bytes[k];
        }
    }

    out_h
}

// Add 1 bit padding to end of message and compress the block if there's not enough room for the 8-byte length.
// Returns the updated hash state and message block that will be used to write the message size.
fn add_padding_byte_and_compress_if_needed(
    mut msg_block: MSG_BLOCK,
    msg_byte_ptr: BLOCK_BYTE_PTR,
    h: STATE,
) -> (STATE, MSG_BLOCK) {
    // Pad the rest such that we have a [u32; 2] block at the end representing the length
    // of the message, and a block of 1 0 ... 0 following the message (i.e. [1 << 7, 0, ..., 0]).
    // Here we rely on the fact that everything beyond the available input is set to 0.
    let index = msg_byte_ptr / INT_SIZE;
    msg_block[index] = set_item_byte_then_zeros(msg_block[index], msg_byte_ptr, 1 << 7);

    // If we don't have room to write the size, compress the block and reset it.
    if msg_byte_ptr >= MSG_SIZE_PTR {
        let h = sha256_compression(msg_block, h);

        // In this case, the final block consists of all zeros with the last 8 bytes containing the length.
        // We set msg_block to all zeros and attach_len_to_msg_block will add the length to the last 8 bytes.
        let msg_block = [0; INT_BLOCK_SIZE];
        (h, msg_block)
    } else {
        (h, msg_block)
    }
}

pub(crate) fn finalize_sha256_blocks(
    message_size: u32,
    mut h: STATE,
    mut msg_block: MSG_BLOCK,
) -> HASH {
    let msg_byte_ptr = message_size % BLOCK_SIZE;

    let (h, mut msg_block) = add_padding_byte_and_compress_if_needed(msg_block, msg_byte_ptr, h);

    msg_block = attach_len_to_msg_block(msg_block, message_size);

    hash_final_block(msg_block, h)
}

/**
 * Given some state of a partially computed sha256 hash and part of the preimage, continue hashing
 * @notice used for complex/ recursive offloading of post-partial hashing
 *
 * @param N - the maximum length of the message to hash
 * @param h - the intermediate hash state
 * @param msg - the preimage to hash
 * @param message_size - the actual length of the preimage to hash
 * @return the intermediate hash state after compressing in msg to h
 */
pub fn partial_sha256_var_interstitial<let N: u32>(
    mut h: [u32; 8],
    msg: [u8; N],
    message_size: u32,
) -> [u32; 8] {
    assert(message_size % BLOCK_SIZE == 0, "Message size must be a multiple of the block size");
    if std::runtime::is_unconstrained() {
        // Safety: running as an unconstrained function
        unsafe {
            __sha_partial_var_interstitial(h, msg, message_size)
        }
    } else {
        let (h, _) = process_full_blocks(msg, message_size, h);

        h
    }
}

/**
 * Given some state of a partially computed sha256 hash and remaining preimage, complete the hash
 * @notice used for traditional partial hashing
 *
 * @param N - the maximum length of the message to hash
 * @param h - the intermediate hash state
 * @param msg - the remaining preimage to hash
 * @param message_size - the size of the current chunk
 * @param real_message_size - the total size of the original preimage
 * @return finalized sha256 hash
 */
pub fn partial_sha256_var_end<let N: u32>(
    mut h: [u32; 8],
    msg: [u8; N],
    message_size: u32,
    real_message_size: u32,
) -> [u8; 32] {
    assert(message_size % BLOCK_SIZE == 0, "Message size must be a multiple of the block size");
    if std::runtime::is_unconstrained() {
        // Safety: running as an unconstrained function
        unsafe {
            h = __sha_partial_var_interstitial(h, msg, message_size);

            // Handle setup of the final msg block.
            // This case is only hit if the msg is less than the block size,
            // or our message cannot be evenly split into blocks.

            finalize_last_sha256_block(h, real_message_size, msg)
        }
    } else {
        let (h, msg_block) = process_full_blocks(msg, message_size, h);
        finalize_sha256_blocks(real_message_size, h, msg_block)
    }
}

unconstrained fn __sha_partial_var_interstitial<let N: u32>(
    mut h: [u32; 8],
    msg: [u8; N],
    message_size: u32,
) -> [u32; 8] {
    let num_full_blocks = message_size / BLOCK_SIZE;
    // Intermediate hash, starting with the canonical initial value
    // Pointer into msg_block on a 64 byte scale
    for i in 0..num_full_blocks {
        let msg_block = build_msg_block(msg, message_size, BLOCK_SIZE * i);
        h = sha256_compression(msg_block, h);
    }
    h
}

mod equivalence_test {

    #[test]
    fn test_implementations_agree(msg: [u8; 100], message_size: u32) {
        let message_size = message_size % 100;
        // Safety: test function
        let unconstrained_sha = unsafe { super::__sha256_var(msg, message_size) };
        let sha = super::sha256_var(msg, message_size);
        assert_eq(sha, unconstrained_sha);
    }
}
