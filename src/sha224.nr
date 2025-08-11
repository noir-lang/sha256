use std::hash::sha256_compression;


use crate::sha256::constants::{
    BLOCK_BYTE_PTR, BLOCK_SIZE, HASH, INITIAL_STATE, INT_BLOCK, INT_BLOCK_SIZE, INT_SIZE,
    INT_SIZE_PTR, MSG_BLOCK, MSG_SIZE_PTR, STATE, TWO_POW_16, TWO_POW_24, TWO_POW_32, TWO_POW_8
};

use crate::sha256::{
    build_msg_block, finalize_last_sha256_block, process_full_blocks, finalize_sha256_blocks
};

use constants as sha224_constants;

pub(crate) mod constants;
mod tests;

// Variable size SHA-224 hash
pub fn sha224_var<let N: u32>(msg: [u8; N], message_size: u64) -> sha224_constants::HASH_SHA224 {
    let message_size = message_size as u32;
    assert(message_size <= N);

    if std::runtime::is_unconstrained() {
        // Safety: SHA224 is running as an unconstrained function.
        unsafe {
            __sha224_var(msg, message_size)
        }
    } else {
        let (mut h, mut msg_block, mut msg_byte_ptr) =
            process_full_blocks(msg, message_size, sha224_constants::INITIAL_STATE_SHA224);

        let hash: HASH = finalize_sha256_blocks(msg, message_size, N, h, msg_block, msg_byte_ptr);
        // Convert 32-byte hash to 28-byte hash for SHA-224
        let mut hash_sha224: sha224_constants::HASH_SHA224 = [0; 28];
        for i in 0..28 {
            hash_sha224[i] = hash[i];
        }
        hash_sha224
    }
}

// Variable size SHA-224 hash
unconstrained fn __sha224_var<let N: u32>(msg: [u8; N], message_size: u32) -> sha224_constants::HASH_SHA224 {
    let num_full_blocks = message_size / BLOCK_SIZE;
    // Intermediate hash, starting with the canonical initial value
    let mut h: STATE = sha224_constants::INITIAL_STATE_SHA224;
    // Pointer into msg_block on a 64 byte scale
    for i in 0..num_full_blocks {
        let (msg_block, _) = build_msg_block(msg, message_size, BLOCK_SIZE * i);
        h = sha256_compression(msg_block, h);
    }

    // Handle setup of the final msg block.
    // This case is only hit if the msg is less than the block size,
    // or our message cannot be evenly split into blocks.

    let hash: HASH = finalize_last_sha256_block(h, message_size, msg);
    // Convert 32-byte hash to 28-byte hash for SHA-224
    let mut hash_sha224: sha224_constants::HASH_SHA224 = [0; 28];
    for i in 0..28 {
        hash_sha224[i] = hash[i];
    }
    hash_sha224
}

mod equivalence_test {

    #[test]
    fn test_implementations_agree(msg: [u8; 100], message_size: u64) {
        let message_size = message_size % 100;
        // Safety: testing
        let unconstrained_sha224 = unsafe { super::__sha224_var(msg, message_size as u32) };
        let sha224 = super::sha224_var(msg, message_size);
        assert_eq(sha224, unconstrained_sha224);
    }
}

