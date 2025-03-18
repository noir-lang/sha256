// A message block is up to 64 bytes taken from the input.
pub(crate) global BLOCK_SIZE: u32 = 64;

// The first index in the block where the 8 byte message size will be written.
pub(crate) global MSG_SIZE_PTR: u32 = 56;

// Size of the message block when packed as 4-byte integer array.
pub(crate) global INT_BLOCK_SIZE: u32 = 16;

// A `u32` integer consists of 4 bytes.
pub(crate) global INT_SIZE: u32 = 4;

// Index of the integer in the `INT_BLOCK` where the length is written.
pub(crate) global INT_SIZE_PTR: u32 = MSG_SIZE_PTR / INT_SIZE;

// Magic numbers for bit shifting.
// Works with actual bit shifting as well as the compiler turns them into * and /
// but circuit execution appears to be 10% faster this way.
pub(crate) global TWO_POW_8: u32 = 256;
pub(crate) global TWO_POW_16: u32 = TWO_POW_8 * 256;
pub(crate) global TWO_POW_24: u32 = TWO_POW_16 * 256;
pub(crate) global TWO_POW_32: u64 = TWO_POW_24 as u64 * 256;

// Index of a byte in a 64 byte block; ie. 0..=63
pub(crate) type BLOCK_BYTE_PTR = u32;

// The foreign function to compress blocks works on 16 pieces of 4-byte integers, instead of 64 bytes.
pub(crate) type INT_BLOCK = [u32; INT_BLOCK_SIZE];

// A message block is a slice of the original message of a fixed size,
// potentially padded with zeros, with neighbouring 4 bytes packed into integers.
pub(crate) type MSG_BLOCK = INT_BLOCK;

// The hash is 32 bytes.
pub(crate) type HASH = [u8; 32];

// The state accumulates the blocks.
// Its overall size is the same as the `HASH`.
pub(crate) type STATE = [u32; 8];

pub(crate) global INITIAL_STATE: STATE =
    [1779033703, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635, 1541459225];

pub(crate) mod test_inputs {
    pub(crate) global DATA: [u8; 192] = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
        25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47,
        48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70,
        71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93,
        94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112,
        113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130,
        131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148,
        149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166,
        167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184,
        185, 186, 187, 188, 189, 190, 191,
    ];
}
