extends RefCounted

# The player manual lives in MANUAL.md so the repository copy and the in-game
# reference cannot drift. This tiny renderer covers the Markdown subset the
# manual uses: headings, bullets, blank-line spacing, and **bold** emphasis.

const MANUAL_PATH := "res://MANUAL.md"

static func load_markdown() -> String:
	if not FileAccess.file_exists(MANUAL_PATH):
		return "# Player Manual\n\nThe manual could not be loaded."
	return FileAccess.get_file_as_string(MANUAL_PATH)

static func to_bbcode(markdown_text: String) -> String:
	var out := ""
	var first_heading := true
	var lines: PackedStringArray = markdown_text.replace("\r\n", "\n").split("\n")
	for raw in lines:
		var line := raw.strip_edges(false, true)
		var trimmed := line.strip_edges(true, true)
		if trimmed == "":
			if out != "" and not out.ends_with("\n\n"):
				out += "\n"
			continue
		var indent := 0
		while indent < line.length() \
				and (line[indent] == " " or line[indent] == "\t"):
			indent += 1
		var text := line.substr(indent)
		if text.begins_with("# "):
			# The panel already carries the manual title; skip the file's H1
			# in-game but keep it for anyone reading the Markdown directly.
			if first_heading:
				first_heading = false
				continue
			out += "[center][font_size=38][b]%s[/b][/font_size][/center]\n" \
				% _inline(text.substr(2))
		elif text.begins_with("## "):
			out += "\n[font_size=32][b][color=#e4c56b]%s[/color][/b][/font_size]\n" \
				% _inline(text.substr(3))
		elif text.begins_with("### "):
			out += "\n[font_size=28][b]%s[/b][/font_size]\n" \
				% _inline(text.substr(4))
		elif text.begins_with("- "):
			var depth := int(indent / 2.0)
			out += "%s• %s\n" % ["    ".repeat(depth), _inline(text.substr(2))]
		else:
			out += _inline(text) + "\n"
	return out

static func _inline(text: String) -> String:
	# Escape untrusted BBCode first, then add the emphasis the manual uses.
	var source := text.replace("[", "[lb]").replace("]", "[rb]")
	var out := ""
	var pos := 0
	while true:
		var start := source.find("**", pos)
		if start < 0:
			out += source.substr(pos)
			break
		var end := source.find("**", start + 2)
		if end < 0:
			out += source.substr(pos)
			break
		out += source.substr(pos, start - pos)
		out += "[b]" + source.substr(start + 2, end - start - 2) + "[/b]"
		pos = end + 2
	return out
