window.BENCHMARK_DATA = {
  "lastUpdate": 1764773590165,
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
      }
    ]
  }
}