#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
crosscheck.py — 番号 + 演员名交叉比对，全程不经过任何模型。

用途：把两个来源（AVWIKI / Scenedex）落盘的 JSONL 做确定性比对，
输出 CSV + 待人工复核清单。模型只在「needs_review=1」的条目上按需介入，
不再承担「是否本人出演」这类语义断言 —— 这正是上次 content_filter 的触发点。

用法：
    python crosscheck.py --a avwiki.jsonl --b scenedex.jsonl -o result.csv
    python crosscheck.py --a a.jsonl --b b.jsonl -o r.csv --threshold 0.86 --names-col performers

输入：JSONL，每行一个对象。字段名自动适配：
    番号: code / 番号 / id / product_id / number
    标题: title / 标题 / name
    演员: performers / actress / actresses / 演员 / cast   (可为 list 或 str，逗号/顿号/斜杠分隔)

输出：
    result.csv     —— 每个番号一行，含匹配结论
    review.jsonl   —— 仅 needs_review=1 的条目，供人工或单条模型复核
"""
import argparse
import csv
import json
import re
import sys
import unicodedata
from difflib import SequenceMatcher

# ---------- 归一化 ----------

_DASHES = "\u2010\u2011\u2012\u2013\u2014\u2015\u2212\uff0d_~ \u30fb\u00b7"


def norm_code(raw):
    """把番号归一成 (PREFIX, 数字) 的规范键。TRE-184 / tre_184 / ＴＲＥ１８４ 全部等价。"""
    if raw is None:
        return ""
    s = unicodedata.normalize("NFKC", str(raw)).strip().upper()
    for d in _DASHES:
        s = s.replace(d, "-")
    m = re.match(r"^([A-Z]+)[-\s]*0*(\d+)(?:[-\s].*)?$", s)
    if m:
        return "%s-%d" % (m.group(1), int(m.group(2)))
    return re.sub(r"[^A-Z0-9]", "", s)


def norm_name(raw):
    """演员名归一：去空白/中点/标点，片假名转平假名，全角转半角。"""
    if raw is None:
        return ""
    s = unicodedata.normalize("NFKC", str(raw)).strip().lower()
    s = re.sub(r"[\s\u30fb\u00b7\.,、，/／|｜_\-]+", "", s)
    out = []
    for ch in s:
        o = ord(ch)
        # 片假名 U+30A1-U+30F6 -> 平假名 U+3041-U+3096
        if 0x30A1 <= o <= 0x30F6:
            out.append(chr(o - 0x60))
        else:
            out.append(ch)
    return "".join(out)


def pick(d, keys):
    for k in keys:
        if k in d and d[k]:
            return d[k]
    return ""


def split_names(v):
    if isinstance(v, (list, tuple)):
        items = [str(x) for x in v]
    else:
        items = re.split(r"[,、，/／|｜;；]+", str(v))
    return [x.strip() for x in items if x and x.strip()]


def best_match(names_a, names_b, threshold):
    """在两个名字集合里找最佳配对，返回 (name_a, name_b, kind, score)。"""
    if not names_a or not names_b:
        return "", "", "missing", 0.0
    na = [norm_name(x) for x in names_a]
    nb = [norm_name(x) for x in names_b]
    # 先求精确交集
    for i, x in enumerate(na):
        for j, y in enumerate(nb):
            if x and x == y:
                return names_a[i], names_b[j], "exact", 1.0
    # 再求模糊最佳
    best = ("", "", "none", 0.0)
    for i, x in enumerate(na):
        for j, y in enumerate(nb):
            if not x or not y:
                continue
            r = SequenceMatcher(None, x, y).ratio()
            if r > best[3]:
                best = (names_a[i], names_b[j], "fuzzy", round(r, 3))
    if best[3] >= threshold:
        return best
    return best[0], best[1], "none", best[3]


def load(path):
    rows = []
    with open(path, "r", encoding="utf-8-sig") as f:
        for ln, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError as e:
                print("[warn] %s:%d 不是合法 JSON，跳过 (%s)" % (path, ln, e), file=sys.stderr)
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--a", required=True, help="来源 A 的 JSONL")
    ap.add_argument("--b", required=True, help="来源 B 的 JSONL")
    ap.add_argument("-o", "--out", default="result.csv")
    ap.add_argument("--review", default="review.jsonl")
    ap.add_argument("--threshold", type=float, default=0.80, help="模糊匹配阈值，默认 0.80")
    ap.add_argument("--code-keys", default="code,番号,id,product_id,number")
    ap.add_argument("--title-keys", default="title,标题,name")
    ap.add_argument("--names-keys", default="performers,actress,actresses,演员,cast")
    args = ap.parse_args()

    ck = args.code_keys.split(",")
    tk = args.title_keys.split(",")
    nk = args.names_keys.split(",")

    A = load(args.a)
    B = load(args.b)

    idx_a, idx_b = {}, {}
    for r in A:
        k = norm_code(pick(r, ck))
        if k:
            idx_a.setdefault(k, r)
    for r in B:
        k = norm_code(pick(r, ck))
        if k:
            idx_b.setdefault(k, r)

    keys = sorted(set(idx_a) | set(idx_b))
    stat = {"both": 0, "only_a": 0, "only_b": 0, "exact": 0, "fuzzy": 0, "none": 0, "missing": 0, "review": 0}

    with open(args.out, "w", encoding="utf-8-sig", newline="") as fo, \
         open(args.review, "w", encoding="utf-8") as fr:
        w = csv.writer(fo)
        w.writerow(["code", "in_avwiki", "in_scenedex", "name_a", "name_b",
                    "match", "score", "needs_review", "title_a", "title_b"])

        for k in keys:
            ra, rb = idx_a.get(k), idx_b.get(k)
            ta = pick(ra, tk) if ra else ""
            tb = pick(rb, tk) if rb else ""
            na = split_names(pick(ra, nk)) if ra else []
            nb = split_names(pick(rb, nk)) if rb else []

            if ra and rb:
                stat["both"] += 1
                name_a, name_b, kind, score = best_match(na, nb, args.threshold)
            elif ra:
                stat["only_a"] += 1
                name_a, name_b, kind, score = (na[0] if na else ""), "", "missing", 0.0
            else:
                stat["only_b"] += 1
                name_a, name_b, kind, score = "", (nb[0] if nb else ""), "missing", 0.0

            stat[kind] = stat.get(kind, 0) + 1
            review = 1 if (kind in ("none", "missing") or (kind == "fuzzy" and score < 0.9)) else 0
            if review:
                stat["review"] += 1
                fr.write(json.dumps({
                    "code": k, "match": kind, "score": score,
                    "name_a": name_a, "name_b": name_b,
                    "title_a": ta, "title_b": tb,
                }, ensure_ascii=False) + "\n")

            w.writerow([k, int(bool(ra)), int(bool(rb)), name_a, name_b, kind, score, review, ta, tb])

    print("A 条数 %d，B 条数 %d，合并键 %d" % (len(A), len(B), len(keys)))
    print("两边都有 %d ｜ 仅 A %d ｜ 仅 B %d" % (stat["both"], stat["only_a"], stat["only_b"]))
    print("姓名 exact %d ｜ fuzzy %d ｜ none %d ｜ missing %d" % (stat["exact"], stat["fuzzy"], stat["none"], stat["missing"]))
    print("待复核 %d 条 -> %s" % (stat["review"], args.review))
    print("明细 -> %s" % args.out)


if __name__ == "__main__":
    main()
