// 要求の JSON と応答の読み取りが、Go のサーバーの protojson と同じフィールド名を使うことを確かめる。
import assert from "node:assert/strict";
import { test } from "node:test";
import { decodeResponse, encodeRequest } from "./shorten.js";

test("encodeRequest", () => {
  assert.equal(encodeRequest("https://bazel.build/"), '{"url":"https://bazel.build/"}');
});

test("decodeResponse", () => {
  assert.equal(decodeResponse('{"code": "1"}'), "1");
});
