# template-table.awk -- the resolved list of one family over a template's
# chain. Variables: base (the database), family (the list), chain (the
# names root to leaf, "empty" first), plain (1: the visible lines bare, for
# the bake; 0: the human table). Walked root to leaf: a template's masks
# hide what its ancestors contributed, then its own lines join with the
# template as origin; a line already visible keeps its first origin.
# Output: one "#   <origin>  <line>" per visible line, "#   (none)" if none;
# plain: one line per visible line, nothing if none.
BEGIN {
	n = split(chain, c, " ")
	for (i = 1; i <= n; i++) {
		a = c[i]
		f = base "/template/" a "/" family ".mask"
		while ((getline l < f) > 0) {
			if (l == "") continue
			for (k = 1; k <= cnt; k++) if (line[k] == l) hide[k] = 1
		}
		close(f)
		f = base "/template/" a "/" family
		while ((getline l < f) > 0) {
			if (l == "" || (l in seen)) continue
			cnt++; line[cnt] = l; origin[cnt] = a; seen[l] = 1
		}
		close(f)
	}
	shown = 0
	for (k = 1; k <= cnt; k++) {
		if (hide[k]) continue
		if (plain) print line[k]; else printf "#   %-16s %s\n", origin[k], line[k]
		shown++
	}
	if (shown == 0 && !plain) print "#   (none)"
}
