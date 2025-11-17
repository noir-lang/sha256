#!/usr/bin/env node

// Oracle Server Template

import express from "express";
import bodyParser from "body-parser";
import cors from "cors";
import { createHash } from 'crypto';

// Basic types
interface ForeignCallInfo {
  function: string;
  inputs: string[][];
}

interface ForeignCallResult {
  values: string[][];
}

// Express app setup
const app = express();
app.use(cors());
app.use(bodyParser.json());

// Main endpoint
app.post("/", async (req, res) => {
  const { method, params, id } = req.body;
  
  if (method === "resolve_foreign_call") {
    const result = await handleForeignCall(params || []);
    res.json({ jsonrpc: "2.0", id, result });
  } else {
    res.json({ jsonrpc: "2.0", id, error: { code: -32601, message: "Method not found" } });
  }
});

async function handleForeignCall(params: any[]): Promise<ForeignCallResult> {
  const [callInfo] = params as [ForeignCallInfo];
  const { function: functionName, inputs } = callInfo;
  

  if (functionName === "getSHA256") {
    return sha256_hash(inputs);
  } else if (functionName === "getSHA224") {
    return sha224_hash(inputs);
  } else {
    throw new Error(`Unknown function: ${functionName}`);
  }
}

function sha256_hash(inputs: any): ForeignCallResult {
  // Input format: [length_string, [byte1_string, byte2_string, ...]]
  // inputs[0] = length (as hex string representing Field element)
  // inputs[1] = actual input array of bytes (as hex strings representing Field elements)
  
  const inputArray = inputs[1] as string[];
  
  const bytes = Uint8Array.from(
    inputArray.map(h => parseInt(h.replace(/^0x/, ''), 16))
  );

  const hashResultBytes: string[] =
  Array.from(createHash('sha256').update(bytes).digest())
       .map(b => b.toString(16).padStart(2, '0'));
  return { values: [hashResultBytes] };
}

function sha224_hash(inputs: any): ForeignCallResult {
  // Input format: [length_string, [byte1_string, byte2_string, ...]]
  // inputs[0] = length (as hex string representing Field element)
  // inputs[1] = actual input array of bytes (as hex strings representing Field elements)
  if (!Array.isArray(inputs) || inputs.length < 2) {
    throw new Error(`Expected inputs array with length and data, got: ${JSON.stringify(inputs)}`);
  }
  
  const inputArray = inputs[1] as string[];
  if (!Array.isArray(inputArray)) {
    throw new Error(`Expected input array at inputs[1], got: ${typeof inputArray}`);
  }
  
  const bytes = Uint8Array.from(
    inputArray.map(h => parseInt(h.replace(/^0x/, ''), 16))
  );

  const hashResultBytes: string[] =
  Array.from(createHash('sha224').update(bytes).digest())
       .map(b => b.toString(16).padStart(2, '0'));
  return { values: [hashResultBytes] };
}

// Health check
app.get("/health", (req, res) => {
  res.json({ status: "ok" });
});

// Start server
const PORT = process.env.PORT || 8095;
app.listen(PORT, () => {
  console.log(`Oracle server running on port ${PORT}`);
});
