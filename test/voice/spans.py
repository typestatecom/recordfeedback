"""Finds the spoken commands in a whisper transcript, and when they were said.

A command is the trigger word and the words after it, up to the next trigger or
a gap in the speech. Where it stops is decided by the pause and not by a list of
phrases, so that a span carrying words this tool does not know is still cut and
then thrown away by the grammar rather than never being looked at.
"""
import json
import sys

TRIGGERS = ("let", "lets", "let's")
# Long enough that two commands said in one breath stay in one span, short
# enough that the sentence after a command is not dragged into it.
GAP = 0.6
# A command is a handful of words. Beyond that the trigger was part of a
# sentence and not an instruction.
MAX_WORDS = 8


def seconds(stamp):
    hours, minutes, rest = stamp.split(":")
    whole, millis = rest.split(",")
    return int(hours) * 3600 + int(minutes) * 60 + int(whole) + int(millis) / 1000.0


def words_of(transcript):
    out = []
    for segment in transcript.get("transcription", []):
        for token in segment.get("tokens", []):
            text = token.get("text", "")
            if text.startswith("[_") or not text.strip():
                continue
            stamps = token.get("timestamps", {})
            if "from" not in stamps or "to" not in stamps:
                continue
            out.append({
                "text": text.strip(),
                "from": seconds(stamps["from"]),
                "to": seconds(stamps["to"]),
                # A recogniser splits "let's" into "let" and "'s", and the
                # apostrophe half is part of the word before it.
                "joins": text.startswith("'"),
            })
    return out


def main():
    data = json.load(open(sys.argv[1]))
    words = words_of(data)
    # Glue the apostrophe back on, so "let" "'s" is one word again.
    glued = []
    for word in words:
        if word["joins"] and glued:
            glued[-1]["text"] += word["text"]
            glued[-1]["to"] = word["to"]
        else:
            glued.append(dict(word))

    spans = []
    index = 0
    while index < len(glued):
        if glued[index]["text"].lower().strip(".,!?") not in TRIGGERS:
            index += 1
            continue
        start = index
        index += 1
        while index < len(glued) and index - start < MAX_WORDS:
            if glued[index]["text"].lower().strip(".,!?") in TRIGGERS:
                break
            if glued[index]["from"] - glued[index - 1]["to"] > GAP:
                break
            index += 1
        said = " ".join(one["text"] for one in glued[start:index])
        spans.append((glued[start]["from"], glued[index - 1]["to"], said.strip()))

    with open(sys.argv[2], "w") as handle:
        for begins, ends, said in spans:
            handle.write("%.3f\t%.3f\t%s\n" % (begins, ends, said))


main()
