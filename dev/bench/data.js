window.BENCHMARK_DATA = {
  "lastUpdate": 1764782300733,
  "repoUrl": "https://github.com/noir-lang/sha256",
  "entries": {
    "ACIR Opcodes": [
      {
        "commit": {
          "author": {
            "email": "15848336+TomAFrench@users.noreply.github.com",
            "name": "Tom French",
            "username": "TomAFrench"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "303f182b2d3696809a4c34a082ce36d01d2a4ca2",
          "message": "chore: add new benchmarking setup (#47)",
          "timestamp": "2025-12-03T14:52:13Z",
          "tree_id": "45181b3118a4c458ef48889de0997a85223bc5d3",
          "url": "https://github.com/noir-lang/sha256/commit/303f182b2d3696809a4c34a082ce36d01d2a4ca2"
        },
        "date": 1764773589077,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "test_sha256_1.json/main",
            "value": 1096,
            "unit": "acir_opcodes"
          },
          {
            "name": "test_sha256_200.json/main",
            "value": 2736,
            "unit": "acir_opcodes"
          },
          {
            "name": "test_sha256_511.json/main",
            "value": 5349,
            "unit": "acir_opcodes"
          },
          {
            "name": "test_sha256_512.json/main",
            "value": 5347,
            "unit": "acir_opcodes"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "15848336+TomAFrench@users.noreply.github.com",
            "name": "Tom French",
            "username": "TomAFrench"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "815d44db19d275d76d349c551e28a597ae507dcf",
          "message": "feat: remove overflow checks when reconstructing `msg_item` (#46)",
          "timestamp": "2025-12-03T17:10:04Z",
          "tree_id": "0cf4e3d0c115a93328d51595af7b1fd120802782",
          "url": "https://github.com/noir-lang/sha256/commit/815d44db19d275d76d349c551e28a597ae507dcf"
        },
        "date": 1764781830218,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "test_sha256_1.json/main",
            "value": 874,
            "unit": "acir_opcodes"
          },
          {
            "name": "test_sha256_200.json/main",
            "value": 2036,
            "unit": "acir_opcodes"
          },
          {
            "name": "test_sha256_511.json/main",
            "value": 3559,
            "unit": "acir_opcodes"
          },
          {
            "name": "test_sha256_512.json/main",
            "value": 3555,
            "unit": "acir_opcodes"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "15848336+TomAFrench@users.noreply.github.com",
            "name": "Tom French",
            "username": "TomAFrench"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9826706fba6bf7caa4691c27c2dc3d0ce2d0eee3",
          "message": "chore: move `make_item` into test file (#48)",
          "timestamp": "2025-12-03T17:15:54Z",
          "tree_id": "36ed432f8962763f3e77535d24484bf549b06a7e",
          "url": "https://github.com/noir-lang/sha256/commit/9826706fba6bf7caa4691c27c2dc3d0ce2d0eee3"
        },
        "date": 1764782175035,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "test_sha256_1.json/main",
            "value": 874,
            "unit": "acir_opcodes"
          },
          {
            "name": "test_sha256_200.json/main",
            "value": 2036,
            "unit": "acir_opcodes"
          },
          {
            "name": "test_sha256_511.json/main",
            "value": 3559,
            "unit": "acir_opcodes"
          },
          {
            "name": "test_sha256_512.json/main",
            "value": 3555,
            "unit": "acir_opcodes"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "26174818+jialinli98@users.noreply.github.com",
            "name": "Jialin Li",
            "username": "jialinli98"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "560067e8786657fca3852354b8951ee46c9dbe98",
          "message": "feat: simplify creating last block (#45)\n\nCo-authored-by: Tom French <15848336+TomAFrench@users.noreply.github.com>",
          "timestamp": "2025-12-03T17:17:40Z",
          "tree_id": "983e57b957aa0b2044514bba13d082842ebfa580",
          "url": "https://github.com/noir-lang/sha256/commit/560067e8786657fca3852354b8951ee46c9dbe98"
        },
        "date": 1764782296472,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "test_sha256_1.json/main",
            "value": 551,
            "unit": "acir_opcodes"
          },
          {
            "name": "test_sha256_200.json/main",
            "value": 1713,
            "unit": "acir_opcodes"
          },
          {
            "name": "test_sha256_511.json/main",
            "value": 3236,
            "unit": "acir_opcodes"
          },
          {
            "name": "test_sha256_512.json/main",
            "value": 3232,
            "unit": "acir_opcodes"
          }
        ]
      }
    ],
    "Circuit Size": [
      {
        "commit": {
          "author": {
            "email": "15848336+TomAFrench@users.noreply.github.com",
            "name": "Tom French",
            "username": "TomAFrench"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "303f182b2d3696809a4c34a082ce36d01d2a4ca2",
          "message": "chore: add new benchmarking setup (#47)",
          "timestamp": "2025-12-03T14:52:13Z",
          "tree_id": "45181b3118a4c458ef48889de0997a85223bc5d3",
          "url": "https://github.com/noir-lang/sha256/commit/303f182b2d3696809a4c34a082ce36d01d2a4ca2"
        },
        "date": 1764773590150,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "test_sha256_1.json/main",
            "value": 36000,
            "unit": "circuit_size"
          },
          {
            "name": "test_sha256_200.json/main",
            "value": 36000,
            "unit": "circuit_size"
          },
          {
            "name": "test_sha256_511.json/main",
            "value": 45649,
            "unit": "circuit_size"
          },
          {
            "name": "test_sha256_512.json/main",
            "value": 49643,
            "unit": "circuit_size"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "15848336+TomAFrench@users.noreply.github.com",
            "name": "Tom French",
            "username": "TomAFrench"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "815d44db19d275d76d349c551e28a597ae507dcf",
          "message": "feat: remove overflow checks when reconstructing `msg_item` (#46)",
          "timestamp": "2025-12-03T17:10:04Z",
          "tree_id": "0cf4e3d0c115a93328d51595af7b1fd120802782",
          "url": "https://github.com/noir-lang/sha256/commit/815d44db19d275d76d349c551e28a597ae507dcf"
        },
        "date": 1764781831914,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "test_sha256_1.json/main",
            "value": 36000,
            "unit": "circuit_size"
          },
          {
            "name": "test_sha256_200.json/main",
            "value": 36000,
            "unit": "circuit_size"
          },
          {
            "name": "test_sha256_511.json/main",
            "value": 43955,
            "unit": "circuit_size"
          },
          {
            "name": "test_sha256_512.json/main",
            "value": 47947,
            "unit": "circuit_size"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "15848336+TomAFrench@users.noreply.github.com",
            "name": "Tom French",
            "username": "TomAFrench"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9826706fba6bf7caa4691c27c2dc3d0ce2d0eee3",
          "message": "chore: move `make_item` into test file (#48)",
          "timestamp": "2025-12-03T17:15:54Z",
          "tree_id": "36ed432f8962763f3e77535d24484bf549b06a7e",
          "url": "https://github.com/noir-lang/sha256/commit/9826706fba6bf7caa4691c27c2dc3d0ce2d0eee3"
        },
        "date": 1764782176147,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "test_sha256_1.json/main",
            "value": 36000,
            "unit": "circuit_size"
          },
          {
            "name": "test_sha256_200.json/main",
            "value": 36000,
            "unit": "circuit_size"
          },
          {
            "name": "test_sha256_511.json/main",
            "value": 43955,
            "unit": "circuit_size"
          },
          {
            "name": "test_sha256_512.json/main",
            "value": 47947,
            "unit": "circuit_size"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "26174818+jialinli98@users.noreply.github.com",
            "name": "Jialin Li",
            "username": "jialinli98"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "560067e8786657fca3852354b8951ee46c9dbe98",
          "message": "feat: simplify creating last block (#45)\n\nCo-authored-by: Tom French <15848336+TomAFrench@users.noreply.github.com>",
          "timestamp": "2025-12-03T17:17:40Z",
          "tree_id": "983e57b957aa0b2044514bba13d082842ebfa580",
          "url": "https://github.com/noir-lang/sha256/commit/560067e8786657fca3852354b8951ee46c9dbe98"
        },
        "date": 1764782298243,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "test_sha256_1.json/main",
            "value": 36000,
            "unit": "circuit_size"
          },
          {
            "name": "test_sha256_200.json/main",
            "value": 36000,
            "unit": "circuit_size"
          },
          {
            "name": "test_sha256_511.json/main",
            "value": 43372,
            "unit": "circuit_size"
          },
          {
            "name": "test_sha256_512.json/main",
            "value": 47364,
            "unit": "circuit_size"
          }
        ]
      }
    ],
    "Brillig Bytecode Size": [
      {
        "commit": {
          "author": {
            "email": "15848336+TomAFrench@users.noreply.github.com",
            "name": "Tom French",
            "username": "TomAFrench"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "303f182b2d3696809a4c34a082ce36d01d2a4ca2",
          "message": "chore: add new benchmarking setup (#47)",
          "timestamp": "2025-12-03T14:52:13Z",
          "tree_id": "45181b3118a4c458ef48889de0997a85223bc5d3",
          "url": "https://github.com/noir-lang/sha256/commit/303f182b2d3696809a4c34a082ce36d01d2a4ca2"
        },
        "date": 1764773591707,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "test_sha256_1",
            "value": 782,
            "unit": "opcodes"
          },
          {
            "name": "test_sha256_200",
            "value": 986,
            "unit": "opcodes"
          },
          {
            "name": "test_sha256_511",
            "value": 1297,
            "unit": "opcodes"
          },
          {
            "name": "test_sha256_512",
            "value": 1298,
            "unit": "opcodes"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "15848336+TomAFrench@users.noreply.github.com",
            "name": "Tom French",
            "username": "TomAFrench"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "815d44db19d275d76d349c551e28a597ae507dcf",
          "message": "feat: remove overflow checks when reconstructing `msg_item` (#46)",
          "timestamp": "2025-12-03T17:10:04Z",
          "tree_id": "0cf4e3d0c115a93328d51595af7b1fd120802782",
          "url": "https://github.com/noir-lang/sha256/commit/815d44db19d275d76d349c551e28a597ae507dcf"
        },
        "date": 1764781834281,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "test_sha256_1",
            "value": 782,
            "unit": "opcodes"
          },
          {
            "name": "test_sha256_200",
            "value": 986,
            "unit": "opcodes"
          },
          {
            "name": "test_sha256_511",
            "value": 1297,
            "unit": "opcodes"
          },
          {
            "name": "test_sha256_512",
            "value": 1298,
            "unit": "opcodes"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "15848336+TomAFrench@users.noreply.github.com",
            "name": "Tom French",
            "username": "TomAFrench"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9826706fba6bf7caa4691c27c2dc3d0ce2d0eee3",
          "message": "chore: move `make_item` into test file (#48)",
          "timestamp": "2025-12-03T17:15:54Z",
          "tree_id": "36ed432f8962763f3e77535d24484bf549b06a7e",
          "url": "https://github.com/noir-lang/sha256/commit/9826706fba6bf7caa4691c27c2dc3d0ce2d0eee3"
        },
        "date": 1764782177907,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "test_sha256_1",
            "value": 782,
            "unit": "opcodes"
          },
          {
            "name": "test_sha256_200",
            "value": 986,
            "unit": "opcodes"
          },
          {
            "name": "test_sha256_511",
            "value": 1297,
            "unit": "opcodes"
          },
          {
            "name": "test_sha256_512",
            "value": 1298,
            "unit": "opcodes"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "26174818+jialinli98@users.noreply.github.com",
            "name": "Jialin Li",
            "username": "jialinli98"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "560067e8786657fca3852354b8951ee46c9dbe98",
          "message": "feat: simplify creating last block (#45)\n\nCo-authored-by: Tom French <15848336+TomAFrench@users.noreply.github.com>",
          "timestamp": "2025-12-03T17:17:40Z",
          "tree_id": "983e57b957aa0b2044514bba13d082842ebfa580",
          "url": "https://github.com/noir-lang/sha256/commit/560067e8786657fca3852354b8951ee46c9dbe98"
        },
        "date": 1764782300717,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "test_sha256_1",
            "value": 728,
            "unit": "opcodes"
          },
          {
            "name": "test_sha256_200",
            "value": 932,
            "unit": "opcodes"
          },
          {
            "name": "test_sha256_511",
            "value": 1243,
            "unit": "opcodes"
          },
          {
            "name": "test_sha256_512",
            "value": 1244,
            "unit": "opcodes"
          }
        ]
      }
    ]
  }
}