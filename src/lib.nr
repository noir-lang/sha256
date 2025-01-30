mod sha256;
mod unconstrained_sha256;

pub use sha256::digest;
pub use sha256::sha256_var;

#[test]
fn test_implementations_agree(msg: [u8; 100], message_size: u64) {
    let message_size = message_size % 100;
    let unconstrained_sha = unsafe { unconstrained_sha256::sha256_var(msg, message_size) };
    let sha = sha256::sha256_var(msg, message_size);
    assert_eq(sha, unconstrained_sha);
}
