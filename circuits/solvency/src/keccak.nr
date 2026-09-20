global RATE_BYTES: u32 = 136;
global RATE_LIMBS: u32 = 17;

pub fn keccak256_single_block<let N: u32>(input: [u8; N]) -> [u8; 32] {
    assert(N < RATE_BYTES - 1);

    let mut block: [u8; RATE_BYTES] = [0; RATE_BYTES];
    for i in 0..N {
        block[i] = input[i];
    }
    block[N] |= 0x01;
    block[RATE_BYTES - 1] |= 0x80;

    let mut state: [u64; 25] = [0; 25];
    for i in 0..RATE_LIMBS {
        let mut limb: Field = 0;
        let mut v: Field = 1;
        for k in 0..8 {
            limb += v * (block[i * 8 + k] as Field);
            v *= 256;
        }
        state[i] = limb as u64;
    }

    state = std::hash::keccakf1600(state);

    let mut result: [u8; 32] = [0; 32];
    for i in 0..4 {
        let lane = state[i] as Field;
        let lane_le: [u8; 8] = lane.to_le_bytes();
        for j in 0..8 {
            result[8 * i + j] = lane_le[j];
        }
    }
    result
}
