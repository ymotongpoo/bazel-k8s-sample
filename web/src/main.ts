// フォームに入力された URL を短縮し、短縮 URL を表示する。
import { shorten } from "./shorten.js";

const form = document.querySelector<HTMLFormElement>("#shorten")!;
const input = document.querySelector<HTMLInputElement>("#url")!;
const output = document.querySelector<HTMLOutputElement>("#result")!;

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  try {
    const code = await shorten(input.value);
    output.value = `${location.origin}/${code}`;
  } catch (err) {
    output.value = String(err);
  }
});
