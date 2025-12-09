# Changelog

## [0.3.0](https://github.com/noir-lang/sha256/compare/v0.2.1...v0.3.0) (2025-12-09)


### ⚠ BREAKING CHANGES

* change length argument to be u32 ([#38](https://github.com/noir-lang/sha256/issues/38))

### Features

* Optimize `attach_len_to_msg_block` ([#49](https://github.com/noir-lang/sha256/issues/49)) ([487a7f1](https://github.com/noir-lang/sha256/commit/487a7f1ea5bc33dc84ae91b5e8d56cacc7241880))
* Optimize `verify_msg_block` ([#42](https://github.com/noir-lang/sha256/issues/42)) ([e247187](https://github.com/noir-lang/sha256/commit/e247187bde004a11cb12a5d7907eb829a5b9366a))
* Remove overflow checks when reconstructing `msg_item` ([#46](https://github.com/noir-lang/sha256/issues/46)) ([815d44d](https://github.com/noir-lang/sha256/commit/815d44db19d275d76d349c551e28a597ae507dcf))
* Remove zero padding check ([#44](https://github.com/noir-lang/sha256/issues/44)) ([953b2b6](https://github.com/noir-lang/sha256/commit/953b2b62c44a00712a6ffbfd8e15d2ced007274d))
* Replace bitshifts with a lookup ([#56](https://github.com/noir-lang/sha256/issues/56)) ([89aa946](https://github.com/noir-lang/sha256/commit/89aa946461628938329cc6dff36fd4594be1dfed))
* Simplify creating last block ([#45](https://github.com/noir-lang/sha256/issues/45)) ([560067e](https://github.com/noir-lang/sha256/commit/560067e8786657fca3852354b8951ee46c9dbe98))


### Miscellaneous Chores

* Change length argument to be u32 ([#38](https://github.com/noir-lang/sha256/issues/38)) ([c204b60](https://github.com/noir-lang/sha256/commit/c204b60dca6236538a0ccaa35578b635c4a74730))

## [0.2.1](https://github.com/noir-lang/sha256/compare/v0.2.0...v0.2.1) (2025-09-03)


### Features

* Handle last block message in process_full_blocks ([#35](https://github.com/noir-lang/sha256/issues/35)) ([aac1edd](https://github.com/noir-lang/sha256/commit/aac1eddb9de506d68940fbf88589a33fb2a65eb5))
* Optimize bitshifts ([#33](https://github.com/noir-lang/sha256/issues/33)) ([d398f9d](https://github.com/noir-lang/sha256/commit/d398f9d0cded272280379b72d97b311e34cc061f))
* Optimize process_full_blocks ([#32](https://github.com/noir-lang/sha256/issues/32)) ([5fb54c8](https://github.com/noir-lang/sha256/commit/5fb54c8d86d83eb62279ac78b7d246f22a66b75a))

## [0.2.0](https://github.com/noir-lang/sha256/compare/v0.1.5...v0.2.0) (2025-08-14)


### ⚠ BREAKING CHANGES

* switch to new bit-shift semantic ([#27](https://github.com/noir-lang/sha256/issues/27))

### Bug Fixes

* Switch to new bit-shift semantic ([#27](https://github.com/noir-lang/sha256/issues/27)) ([3430661](https://github.com/noir-lang/sha256/commit/3430661b2b9a87cb8a10801ae4418b0da67f6b08))

## [0.1.5](https://github.com/noir-lang/sha256/compare/v0.1.4...v0.1.5) (2025-08-13)


### Features

* Add sha224 support ([#28](https://github.com/noir-lang/sha256/issues/28)) ([de3af27](https://github.com/noir-lang/sha256/commit/de3af272f83d301551682d0518c0bbf0d011d192))
* Added partial hash computation ([#16](https://github.com/noir-lang/sha256/issues/16)) ([98bc1c6](https://github.com/noir-lang/sha256/commit/98bc1c6fdedf6112486c575ee342741d060afd88))
* Remove overflow checks in `verify_msg_len` function ([#24](https://github.com/noir-lang/sha256/issues/24)) ([dbffe11](https://github.com/noir-lang/sha256/commit/dbffe11de6ddf8b6d893ba0b6a67ed88a4b53b31))

## [0.1.4](https://github.com/noir-lang/sha256/compare/v0.1.3...v0.1.4) (2025-05-21)


### Features

* Integer division simplification ([#19](https://github.com/noir-lang/sha256/issues/19)) ([ab18ee7](https://github.com/noir-lang/sha256/commit/ab18ee7387a361339a4dbbf8fd540e144abd3a5d))

## [0.1.3](https://github.com/noir-lang/sha256/compare/v0.1.2...v0.1.3) (2025-04-18)


### Bug Fixes

* Fix warnings ([#17](https://github.com/noir-lang/sha256/issues/17)) ([5a9d90f](https://github.com/noir-lang/sha256/commit/5a9d90fa734bbb9f481c95ef97ab89e4089d32e2))

## [0.1.2](https://github.com/noir-lang/sha256/compare/v0.1.1...v0.1.2) (2025-02-13)


### Features

* **performance:** Always inline certain small methods ([#13](https://github.com/noir-lang/sha256/issues/13)) ([96c43cc](https://github.com/noir-lang/sha256/commit/96c43ccf8fd92502e0e83836ecde0f89e2b09799))

## [0.1.1](https://github.com/noir-lang/sha256/compare/v0.1.0...v0.1.1) (2025-02-04)


### Features

* Add a sha256 implementation which is optimized for unconstrained runtime ([#9](https://github.com/noir-lang/sha256/issues/9)) ([a333d3c](https://github.com/noir-lang/sha256/commit/a333d3cd86380cf191849b4daadf94bb1b1f2ec9))

## 0.1.0 (2025-01-21)


### Features

* Initial release
