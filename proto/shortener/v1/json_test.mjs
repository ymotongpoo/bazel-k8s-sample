// 生成したコードで作ったメッセージを JSON にし、フィールド名が Go の protojson と同じになることを確かめる。
import assert from "node:assert";
import { create, toJsonString } from "@bufbuild/protobuf";
import { ShortenRequestSchema } from "./shortener_pb.js";

const req = create(ShortenRequestSchema, { url: "https://bazel.build/" });
assert.equal(toJsonString(ShortenRequestSchema, req), '{"url":"https://bazel.build/"}');
