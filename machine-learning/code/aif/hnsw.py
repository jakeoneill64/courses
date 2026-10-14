import heapq
import math

import numpy as np


class HNSW:
    """Hierarchical navigable small-world graph over unit vectors, searched by cosine distance."""

    def __init__(
        self, vectors: np.ndarray, m: int = 16, ef_construction: int = 100, seed: int = 0
    ):
        self.vectors = np.ascontiguousarray(vectors, dtype=np.float32)
        self.m, self.ef_construction = m, ef_construction
        self.links: list[dict[int, list[int]]] = []
        self.entry, self.top = -1, -1
        self.computed = 0
        rng = np.random.default_rng(seed)
        # snippet:begin levels
        levels = np.floor(-np.log(rng.random(len(vectors))) / math.log(m)).astype(int)
        # snippet:end levels
        for i, level in enumerate(levels):
            self.insert(i, int(level))

    def distances(self, q: np.ndarray, ids: list[int]) -> np.ndarray:
        self.computed += len(ids)
        return 1.0 - self.vectors[ids] @ q

    # snippet:begin search-layer
    def search_layer(
        self, q: np.ndarray, entries: list[int], ef: int, level: int
    ) -> list[tuple[float, int]]:
        visited = set(entries)
        start = self.distances(q, entries)
        candidates = [(d, e) for d, e in zip(start, entries)]
        heapq.heapify(candidates)
        best = [(-d, e) for d, e in zip(start, entries)]
        heapq.heapify(best)
        while candidates:
            d, node = heapq.heappop(candidates)
            if d > -best[0][0]:
                break
            fresh = [n for n in self.links[level][node] if n not in visited]
            visited.update(fresh)
            if not fresh:
                continue
            for dn, n in zip(self.distances(q, fresh), fresh):
                if len(best) < ef or dn < -best[0][0]:
                    heapq.heappush(candidates, (dn, n))
                    heapq.heappush(best, (-dn, n))
                    if len(best) > ef:
                        heapq.heappop(best)
        return sorted((-d, n) for d, n in best)

    # snippet:end search-layer

    # snippet:begin insert
    def insert(self, i: int, level: int) -> None:
        while len(self.links) <= level:
            self.links.append({})
        for l in range(level + 1):
            self.links[l][i] = []
        if self.entry < 0:
            self.entry, self.top = i, level
            return
        q = self.vectors[i]
        entries = [self.entry]
        for l in range(self.top, level, -1):
            entries = [self.search_layer(q, entries, 1, l)[0][1]]
        for l in range(min(level, self.top), -1, -1):
            found = self.search_layer(q, entries, self.ef_construction, l)
            limit = 2 * self.m if l == 0 else self.m
            self.links[l][i] = [n for _, n in found[: self.m]]
            for n in self.links[l][i]:
                links = self.links[l][n]
                links.append(i)
                if len(links) > limit:
                    keep = np.argsort(self.distances(self.vectors[n], links))[:limit]
                    self.links[l][n] = [links[k] for k in keep]
            entries = [n for _, n in found]
        if level > self.top:
            self.entry, self.top = i, level

    # snippet:end insert

    # snippet:begin search
    def search(self, q: np.ndarray, k: int, ef: int) -> list[int]:
        entries = [self.entry]
        for l in range(self.top, 0, -1):
            entries = [self.search_layer(q, entries, 1, l)[0][1]]
        return [n for _, n in self.search_layer(q, entries, max(ef, k), 0)[:k]]

    # snippet:end search
