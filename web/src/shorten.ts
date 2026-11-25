// 短縮 URL の API の要求と応答を、protoのスキーマから生成した型で読み書きする。
import { create, fromJsonString, toJsonString } from "@bufbuild/protobuf";
import {
  ShortenRequestSchema,
  ShortenResponseSchema,
} from "../../proto/shortener/v1/shortener_pb.js";

export function encodeRequest(url: string): string {
  return toJsonString(ShortenRequestSchema, create(ShortenRequestSchema, { url }));
}

export function decodeResponse(json: string): string {
  return fromJsonString(ShortenResponseSchema, json).code;
}

export async function shorten(url: string): Promise<string> {
  const res = await fetch("/shorten", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: encodeRequest(url),
  });
  if (!res.ok) {
    throw new Error(`shorten failed: ${res.status}`);
  }
  return decodeResponse(await res.text());
}
