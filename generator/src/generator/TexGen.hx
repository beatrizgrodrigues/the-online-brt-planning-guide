package generator;

import generator.tex.*;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import transform.Document;

import Assertion.*;

using Literals;
using StringTools;
using parser.TokenTools;

class TexGen {
	static var FILE_BANNER = "
	% The Online BRT Planning Guide
	% This file has been generated; do not edit manually!
	".doctrim();

	var destDir:String;
	var preamble:StringBuf;
	var bufs:Map<String,StringBuf>;

	static var texEscapes = ~/([%{}%#\$\/])/;  // FIXME complete

	public function gent(text:String)
	{
		
		text = text.split("\\").map(texEscapes.replace.bind(_, "\\$1")).join("\\textbackslash{}");
		// FIXME complete
		return text;
	}

	public function genp(pos:Position)
	{
		var lpos = pos.toLinePosition();
		if (Main.debug)
			return '% @ ${lpos.src}: lines ${lpos.lines.min + 1}-${lpos.lines.max}: chars ${lpos.chars.min + 1}-${lpos.chars.max}\n';  // TODO slow, be careful!
		return '% @ ${pos.src}: bytes ${pos.min + 1}-${pos.max}\n';
	}

	public function genh(h:HElem)
	{
		switch h.def {
		case HList(li):
			var buf = new StringBuf();
			for (i in li)
				buf.add(genh(i));
			return buf.toString();
		case Word(word):
			return gent(word);
		case Code(code):
			return '\\code{${gent(code)}}';
		case Wordspace:
			return " ";
		case Emphasis(h):
			return '\\emphasis{${genh(h)}}';
		case Highlight(h):
			return '\\highlight{${genh(h)}}';
		}
	}

	public function genv(v:TElem, at:String)
	{
		assert(!at.endsWith(".tex"), at, "should not but a directory");
		switch v.def {
		case TVList(li):
			var buf = new StringBuf();
			for (i in li)
				buf.add(genv(i, at));
			return buf.toString();
		case TParagraph(h):
			return '${genh(h)}\\par\n${genp(v.pos)}\n';
		case TVolume(name, count, id, children):
			var path = Path.join([at, id.split(".")[1]+".tex"]);
			var dir = Path.join([at, id.split(".")[1]]);
			var buf = new StringBuf();
			bufs[path] = buf;
			buf.add(FILE_BANNER);
			buf.add('\n\n\\volume{${genh(name)}}\n\\label{$id}\n${genp(v.pos)}\n${genv(children, dir)}');
			return '\\input{$path}\n\n';
		case TChapter(name, count, id, children):
			var path = Path.join([at, id.split(".")[3]+".tex"]);
			var buf = new StringBuf();
			bufs[path] = buf;
			buf.add('\\chapter{${genh(name)}}\n\\label{$id}\n${genp(v.pos)}\n${genv(children, at)}');
			return '\\input{$path}\n\n';
		case TSection(name, count, id, children):
			return '\\section{${genh(name)}}\n\\label{$id}\n${genp(v.pos)}\n${genv(children, at)}';
		case TSubSection(name, count, id, children):
			return '\\subsection{${genh(name)}}\n\\label{$id}\n${genp(v.pos)}\n${genv(children, at)}';
		case TSubSubSection(name, count, id, children):
			return '\\subsubsection{${genh(name)}}\n\\label{$id}\n${genp(v.pos)}\n${genv(children, at)}';
		case TFigure(size, path, caption, cright, cnt, id):
			path = sys.FileSystem.absolutePath(path);  // FIXME maybe move to transform
			// TODO handle size
			// TODO escape path
			// TODO escape count
			// TODO enable (uncomment)
			return '% \\img{\\hsize}{$path}\n% \\fignote{$cnt}{${genh(caption)}}{${genh(cright)}}\n\n';  // FIXME more neutral names
		case TBox(name, contents, count, id):
			weakAssert(name == null, "not sure what to do with the box name yet");
			return '\\beginbox\n% TODO name: ${genh(name)}\n\n${genv(contents, at)}\\endbox\n${genp(v.pos)}\n';
		case TQuotation(text, by):
			return '\\quotation{${genh(text)}}{${genh(by)}}\n${genp(v.pos)}\n';
		case TList(li):
			var buf = new StringBuf();
			buf.add("\\begin{itemize}\n");
			for (i in li)
				switch i.def {
				case TParagraph(h):
					buf.add('\\item ${genh(h)}${genp(i.pos)}');
				case _:
					buf.add('\\item {${genv(i, at)}}\n');
				}
			buf.add("\\end{itemize}\n");
			buf.add(genp(v.pos));
			buf.add("\n");
			return buf.toString();
		case TLaTeXPreamble(path):
			// TODO validate path (or has Transform done so?)
			preamble.add('% included from `$path`\n');
			preamble.add(genp(v.pos));
			preamble.add(File.getContent(path).trim());
			preamble.add("\n\n");
			return "";
		case TLaTeXExport(path):
			assert(FileSystem.isDirectory(destDir));
			assert(Sys.systemName() != "Windows", Sys.systemName());
			Sys.command("cp", ["-r", path, destDir]);  // FIXME Windows, validate, make it less fragile
			return "";
		case THtmlApply(_):
			return "";
		case TTable(_):
			return LargeTable.gen(v, this, at);
		}
	}

	public function writeDocument(doc:Document)
	{
		FileSystem.createDirectory(destDir);
		preamble = new StringBuf();
		preamble.add(FILE_BANNER);
		preamble.add("\n\n");

		var contents = genv(doc, "./");

		var root = new StringBuf();
		root.add(preamble.toString());
		root.add("\\begin{document}\n\n");
		root.add(contents);
		root.add("\\end{document}\n");
		bufs["book.tex"] = root;

		for (p in bufs.keys()) {
			var path = Path.join([destDir, p]);
			FileSystem.createDirectory(Path.directory(path));
			File.saveContent(path, bufs[p].toString());
		}
	}

	public function new(destDir)
	{
		// TODO validate destDir
		this.destDir = destDir;
		bufs = new Map();
	}
}

