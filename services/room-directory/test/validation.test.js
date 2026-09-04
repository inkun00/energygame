import assert from "node:assert/strict";
import test from "node:test";
import { isValidIpv4, isValidPort, isValidRoomCode, sha256Hex } from "../src/index.js";

test("room code accepts exactly six digits without a leading zero", () => {
  assert.equal(isValidRoomCode("123456"), true);
  assert.equal(isValidRoomCode("012345"), false);
  assert.equal(isValidRoomCode("12345"), false);
  assert.equal(isValidRoomCode("12345A"), false);
});

test("game port validation rejects privileged and invalid ports", () => {
  assert.equal(isValidPort(8910), true);
  assert.equal(isValidPort(80), false);
  assert.equal(isValidPort(65536), false);
  assert.equal(isValidPort("8910"), false);
});

test("IPv4 validation checks every octet", () => {
  assert.equal(isValidIpv4("203.0.113.42"), true);
  assert.equal(isValidIpv4("999.1.1.1"), false);
  assert.equal(isValidIpv4("0.0.0.0"), false);
  assert.equal(isValidIpv4("2001:db8::1"), false);
});

test("host token is stored as a deterministic SHA-256 hash", async () => {
  const digest = await sha256Hex("test-token");
  assert.equal(digest, "4c5dc9b7708905f77f5e5d16316b5dfb425e68cb326dcd55a860e90a7707031e");
});
