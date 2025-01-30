use std::field::bn254::assert_lt;
use std::hash::sha256_compression;
use std::runtime::is_unconstrained;

// Implementation of SHA-256 mapping a byte array of variable length to
// 32 bytes.

// A message block is up to 64 bytes taken from the input.
global BLOCK_SIZE: u32 = 64;

// The first index in the block where the 8 byte message size will be written.
global MSG_SIZE_PTR: u32 = 56;

// Size of the message block when packed as 4-byte integer array.
global INT_BLOCK_SIZE: u32 = 16;

// A `u32` integer consists of 4 bytes.
global INT_SIZE: u32 = 4;

// Index of the integer in the `INT_BLOCK` where the length is written.
global INT_SIZE_PTR: u32 = MSG_SIZE_PTR / INT_SIZE;

// Magic numbers for bit shifting.
// Works with actual bit shifting as well as the compiler turns them into * and /
// but circuit execution appears to be 10% faster this way.
global TWO_POW_8: u32 = 256;
global TWO_POW_16: u32 = TWO_POW_8 * 256;
global TWO_POW_24: u32 = TWO_POW_16 * 256;

// Index of a byte in a 64 byte block; ie. 0..=63
type BLOCK_BYTE_PTR = u32;

// The foreign function to compress blocks works on 16 pieces of 4-byte integers, instead of 64 bytes.
type INT_BLOCK = [u32; INT_BLOCK_SIZE];

// A message block is a slice of the original message of a fixed size,
// potentially padded with zeros, with neighbouring 4 bytes packed into integers.
type MSG_BLOCK = INT_BLOCK;

// The hash is 32 bytes.
type HASH = [u8; 32];

// The state accumulates the blocks.
// Its overall size is the same as the `HASH`.
type STATE = [u32; 8];

// Variable size SHA-256 hash
pub unconstrained fn sha256_var<let N: u32>(msg: [u8; N], message_size: u64) -> HASH {
    let message_size = message_size as u32;
    assert(message_size <= N);
    let num_full_blocks = message_size / BLOCK_SIZE;
    // Intermediate hash, starting with the canonical initial value
    let mut h: STATE = [
        1779033703, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635,
        1541459225,
    ];
    // Pointer into msg_block on a 64 byte scale
    for i in 0..num_full_blocks {
        let msg_start = BLOCK_SIZE * i;
        let (msg_block, _) = build_msg_block(msg, message_size, msg_start);

        h = sha256_compression(msg_block, h);
    }

    // Handle setup of the final msg block.
    // This case is only hit if the msg is less than the block size,
    // or our message cannot be evenly split into blocks.
    let modulo = message_size % BLOCK_SIZE;
    let (mut msg_block, mut msg_byte_ptr): (INT_BLOCK, u32) = if modulo != 0 {
        let msg_start = BLOCK_SIZE * num_full_blocks;
        let (new_msg_block, new_msg_byte_ptr) = build_msg_block(msg, message_size, msg_start);

        (new_msg_block, new_msg_byte_ptr)
    } else {
        // If we had modulo == 0 then it means the last block was full,
        // and we can reset the pointer to zero to overwrite it.
        ([0; INT_BLOCK_SIZE], 0)
    };

    // Pad the rest such that we have a [u32; 2] block at the end representing the length
    // of the message, and a block of 1 0 ... 0 following the message (i.e. [1 << 7, 0, ..., 0]).
    // Here we rely on the fact that everything beyond the available input is set to 0.
    msg_block = update_block_item(
        msg_block,
        msg_byte_ptr,
        |msg_item| set_item_byte_then_zeros(msg_item, msg_byte_ptr, 1 << 7),
    );

    // If we don't have room to write the size, compress the block and reset it.
    msg_byte_ptr = if msg_byte_ptr >= MSG_SIZE_PTR {
        h = sha256_compression(msg_block, h);
        // `attach_len_to_msg_block` will zero out everything after the `msg_byte_ptr`.
        0
    } else {
        msg_byte_ptr + 1
    };
    msg_block = attach_len_to_msg_block(msg_block, msg_byte_ptr, message_size);

    hash_final_block(msg_block, h)
}

// Take `BLOCK_SIZE` number of bytes from `msg` starting at `msg_start`.
// Returns the block and the length that has been copied rather than padded with zeros.
unconstrained fn build_msg_block<let N: u32>(
    msg: [u8; N],
    message_size: u32,
    msg_start: u32,
) -> (MSG_BLOCK, BLOCK_BYTE_PTR) {
    let mut msg_block: MSG_BLOCK = [0; INT_BLOCK_SIZE];

    // We insert `BLOCK_SIZE` bytes (or up to the end of the message)
    let block_input = if msg_start + BLOCK_SIZE > message_size {
        message_size - msg_start
    } else {
        BLOCK_SIZE
    };

    // Figure out the number of items in the int array that we have to pack.
    // e.g. if the input is [0,1,2,3,4,5] then we need to pack it as 2 items: [0123, 4500]
    let mut int_input = block_input / INT_SIZE;
    if block_input % INT_SIZE != 0 {
        int_input = int_input + 1;
    };

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
            msg_item = lshift8(msg_item, 1) + msg_byte as u32;
        }
        msg_block[i] = msg_item;
    }

    // Returning the index as if it was a 64 byte array.
    // We have to project it down to 16 items and bit shifting to get a byte back if we need it.
    (msg_block, block_input)
}

// Apply a function on the block item which the pointer indicates.
fn update_block_item<Env>(
    mut msg_block: MSG_BLOCK,
    msg_byte_ptr: BLOCK_BYTE_PTR,
    f: fn[Env](u32) -> u32,
) -> MSG_BLOCK {
    let i = msg_byte_ptr / INT_SIZE;
    msg_block[i] = f(msg_block[i]);
    msg_block
}

// Set the rightmost `zeros` number of bytes to 0.
fn set_item_zeros(item: u32, zeros: u8) -> u32 {
    lshift8(rshift8(item, zeros), zeros)
}

// Replace one byte in the item with a value, and set everything after it to zero.
fn set_item_byte_then_zeros(msg_item: u32, msg_byte_ptr: BLOCK_BYTE_PTR, msg_byte: u8) -> u32 {
    let zeros = INT_SIZE - msg_byte_ptr % INT_SIZE;
    let zeroed_item = set_item_zeros(msg_item, zeros as u8);
    let new_item = byte_into_item(msg_byte, msg_byte_ptr);
    zeroed_item + new_item
}

// Project a byte into a position in a field based on the overall block pointer.
// For example putting 1 into pointer 5 would be 100, because overall we would
// have [____, 0100] with indexes [0123,4567].
fn byte_into_item(msg_byte: u8, msg_byte_ptr: BLOCK_BYTE_PTR) -> u32 {
    let mut msg_item = msg_byte as u32;
    // How many times do we have to shift to the left to get to the position we want?
    let max_shifts = INT_SIZE - 1;
    let shifts = max_shifts - msg_byte_ptr % INT_SIZE;
    lshift8(msg_item, shifts as u8)
}

// Construct a field out of 4 bytes.
fn make_item(b0: u8, b1: u8, b2: u8, b3: u8) -> u32 {
    let mut item = b0 as u32;
    item = lshift8(item, 1) + b1 as u32;
    item = lshift8(item, 1) + b2 as u32;
    item = lshift8(item, 1) + b3 as u32;
    item
}

// Shift by 8 bits to the left between 0 and 4 times.
// Checks `is_unconstrained()` to just use a bitshift if we're running in an unconstrained context,
// otherwise multiplies by 256.
fn lshift8(item: u32, shifts: u8) -> u32 {
    if item == 0 {
        0
    } else {
        // Brillig wouldn't shift 0<<4 without overflow.
        item << (8 * shifts)
    }
}

// Shift by 8 bits to the right between 0 and 4 times.
// Checks `is_unconstrained()` to just use a bitshift if we're running in an unconstrained context,
// otherwise divides by 256.
fn rshift8(item: u32, shifts: u8) -> u32 {
    item >> (8 * shifts)
}

// Zero out all bytes between the end of the message and where the length is appended,
// then write the length into the last 8 bytes of the block.
unconstrained fn attach_len_to_msg_block(
    mut msg_block: MSG_BLOCK,
    mut msg_byte_ptr: BLOCK_BYTE_PTR,
    message_size: u32,
) -> MSG_BLOCK {
    // We assume that `msg_byte_ptr` is less than 57 because if not then it is reset to zero before calling this function.
    // In any case, fill blocks up with zeros until the last 64 bits (i.e. until msg_byte_ptr = 56).
    // There can be one item which has to be partially zeroed.
    let modulo = msg_byte_ptr % INT_SIZE;
    if modulo != 0 {
        // Index of the block in which we find the item we need to partially zero.
        let i = msg_byte_ptr / INT_SIZE;
        let zeros = INT_SIZE - modulo;
        msg_block[i] = set_item_zeros(msg_block[i], zeros as u8);
        msg_byte_ptr = msg_byte_ptr + zeros;
    }

    // The rest can be zeroed without bit shifting anything.
    for i in (msg_byte_ptr / INT_SIZE)..INT_SIZE_PTR {
        msg_block[i] = 0;
    }

    // Set the last two 4 byte ints as the first/second half of the 8 bytes of the length.
    let len = 8 * message_size;
    let len_bytes: [u8; 8] = (len as Field).to_be_bytes();
    for i in 0..=1 {
        let shift = i * 4;
        msg_block[INT_SIZE_PTR + i] = make_item(
            len_bytes[shift],
            len_bytes[shift + 1],
            len_bytes[shift + 2],
            len_bytes[shift + 3],
        );
    }
    msg_block
}

// Perform the final compression, then transform the `STATE` into `HASH`.
fn hash_final_block(msg_block: MSG_BLOCK, mut state: STATE) -> HASH {
    // Hash final padded block
    state = sha256_compression(msg_block, state);

    // Return final hash as byte array
    let mut out_h: HASH = [0; 32];
    for j in 0..8 {
        let h_bytes: [u8; 4] = (state[j] as Field).to_be_bytes();
        for k in 0..4 {
            out_h[4 * j + k] = h_bytes[k];
        }
    }

    out_h
}

