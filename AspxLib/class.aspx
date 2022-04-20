<%@ Import Namespace="System.Data" %><%@
Import Namespace="System.Data.Common" %><%
function DbHelper(dbName, provider) {
	var prv = new Object, pub = this;
	this.dbName = dbName || "file::memory:";
	this.provider = provider || "Mono.Data.Sqlite";

	function query(sql, par, firstOnly) {
		var rows = new Array;
		rows.toString = function() { return tojson(rows); };
		rows.forEach = function(func) { for(var i = 0; i < rows.length; i++) func(rows[i], i); };
		var rd = initParam(sql, par).ExecuteReader();
		while(rd.Read()) {
			var row = new Object;
			row.toString = function() { return tojson(row); }
			for(var i = 0 ; i < rd.FieldCount; i++) row[rd.GetName(i)] = rd[i];
			rows.push(row);
			if(firstOnly) break;
		}
		rd.Close();
		return rows;
	}
	function fetch(sql, par) { return query(sql, par, true)[0]; }
	function scalar(sql, par) { return initParam(sql, par).ExecuteScalar(); }
	function none(sql, par) { return initParam(sql, par).ExecuteNonQuery(); }
	function insert(tbl, rows, expr) {
		if(!(rows instanceof Array)) rows = [ rows ];
		var trans = getCmd().Connection.BeginTransaction();
		if(!expr) expr = new Object;
		getCmd().Transaction = trans;
		for(var i = 0; i < rows.length; i++) {
			var row = rows[i];
			var cols = new Array, vals = new Array;
			for(var x in row) {
				if(row[x] instanceof Function) continue;
				cols.push(toname(x));
				vals.push(!expr[x] ? "@" + x : expr[x]);
			}
			none("insert into " + toname(tbl) + "(" + cols.join(", ") + ") values(" + vals.join(", ") + ")", row);
		}
		trans.Commit();
	}
	function update(tbl, data, where, expr) {
		if(!expr) expr = new Object;
		var cols = new Array, cond = new Array, par = new Object;
		for(var x in data) {
			if(data[x] instanceof Function) continue;
			cols.push(toname(x) + "=" + (expr[x] || ("@" + x )));
			par[x] = data[x];
		}
		for(var x in where) {
			cond.push(toname(x) + "=" + (expr[x] || ("@" + x )));
			par[x] = where[x];
		}
		if(!cond.length || !cols.length) return 0;
		return none("update " + toname(tbl) + " set " + cols.join(", ") + " where " + cond.join(" and "), par);
	}
	function create(tbl, cols) {
		var dic = {
			"System.Data.SqlClient": " identity primary key",
			"MySql.Data.MySqlClient" : " auto_increment primary key"
		};
		for(var i = 0; i < cols.length; i++) {
			var col = cols[i];
			if(!(col instanceof Array)) col = [col];
			cols[i] = col[0];
			if(col[1] === [].x) col[1] = null;
			if(col[1] !== null) cols[i] += " not null default (" + col[1] + ")";
			if(col[2]) cols[i] += dic[pub.provider] || " primary key autoincrement";
		}
		none("create table " + toname(tbl) + "(" + cols.join(", ") + ")");
	}
	function close() {
		if(!prv.cmd) return;
		prv.cmd.Connection.Close();
		prv.cmd = null;
	}
	function toname(name) {
		return pub.provider == "System.Data.SqlClient" ? ("[" + name + "]") : ("`" + name + "`");
	}
	function table(tbl) {
		var provider = pub.provider;
		tbl = [ tbl ];
		var _select = "*", where = "", groupby = "", having = "", orderby = "", limit = "";
		var ins = new Object;
		ins.join = function(str, dir){
			if(!dir) dir = "left";
			tbl.push(" " + dir + " join " + str);
			return ins;
		};
		ins.where = function(str){ where = " where " + str; return ins; };
		ins.groupby = function(str){ groupby = " group by " + str; return ins; };
		ins.having = function(str){ having = " having " + str; return ins; };
		ins.orderby = function(str){ orderby = " order by " + str; return ins; };
		ins.limit = function(x, y) {
			if(provider != "System.Data.SqlClient") limit = " limit " + x + ", " + y;
			else limit = " offset " + x + " rows fetch next " + y + " rows only";
			return ins;
		};
		ins.astable = function(str) {
			tbl = [ "(" + ins + ") " + str ];
			where = groupby = having = orderby = limit = "";
			_select = "*"; return ins;
		};
		ins.select = ins.field = function(str){ _select = str; return ins; };
		ins.query = function(par) { return query(ins.toString(), par || ins.pagePar); };
		ins.fetch = function(par) { return fetch(ins.toString(), par); };
		ins.scalar = function(par){ return scalar(ins.toString(), par); };
		ins.page = function(sort, size, page, par) {
			ins.pagePar = par; limit = "";
			pub.pageArg = pub.pager = new Object;
			pub.pageArg.toString = function() { return tojson(this); };
			var bakCol = _select;
			pub.pageArg.rownum = ins.select("count(0)").scalar(par);
			pub.pageArg.pagenum = Math.ceil(pub.pageArg.rownum / size);
			pub.pageArg.curpage = Math.min(page || 1, pub.pageArg.pagenum);
			pub.pageArg.pagesize = size;
			var start = Math.max(pub.pageArg.curpage - 1, 0) * size;
			return ins.select(bakCol).orderby(sort).limit(start, size);
		};
		ins.toString = function() { return "select " + _select + " from " + tbl.join(" ") + where + groupby + having + orderby + limit; }
		return ins;
	}

	function getCmd() {
		if(prv.cmd) return prv.cmd;
		var dbf = DbProviderFactories.GetFactory(pub.provider);
		var conn = dbf.CreateConnection();
		conn.ConnectionString = "Data Source=" + pub.dbName;
		prv.cmd = conn.CreateCommand(); conn.Open(); return prv.cmd;
	}
	function initParam(sql, par) {
		getCmd().Parameters.Clear();
		prv.cmd.CommandText = sql;
		pub.lastSql = { sql: sql, par : par || new Object };
		pub.lastSql.toString = function() { return tojson(pub.lastSql); };
		if(!par) return prv.cmd;
		for(var x in par) {
			if("function" == typeof par[x]) continue;
			var p = prv.cmd.CreateParameter();
			p.ParameterName = x; p.Value = par[x];
			prv.cmd.Parameters.Add(p);
		}
		return prv.cmd;
	}
	this.query = query; this.scalar = scalar; this.none = none; this.insert = insert; this.fetch = fetch;
	this.update = update; this.create = create; this.close = close; this.table = table;
};
DbHelper.tojson = function(obj) {
	switch(typeof obj) {
		case "string": return toStr();
		case "number": return toNum();
		case "object": return toObj(obj);
		case "boolean": return toBool();
		case "date": return toTime();
		case "function": return obj;
		case "undefined": return "null";
		default: return '"unknown"';
	}
	function toStr() { return '"' + obj.replace(/[\"\\]/g, function(str) { return "\\" + str; }).replace(/\r/g, "\\r").replace(/\n/g, "\\n").replace(/\t/g, "\\t") + '"'; }
	function toNum() { return obj; }
	function toBool() { return obj ? "true" : "false"; }
	function toObj() {
		if(!obj) return "null";
		if(obj instanceof Array) return toArr();
		var arr = new Array;
		for(var x in obj) {
			if("function" == typeof obj[x]) continue;
			arr.push(tojson(x + "") + ":" + tojson(obj[x]));
		}
		return "{" + arr.join(",") + "}";
	}
	function toArr() {
		var arr = new Array;
		for(var i = 0; i < obj.length; i++) arr.push(tojson(obj[i]));
		return "[" + arr.join(",") + "]";
	}
	function toTime() { return '"' + obj.ToString("yyyy-MM-dd HH:mm:ss") + '"'; }
}
DbHelper.fromjson = function(str) {
	var regTag = /[\{\[\"ntf\d\.\-]/, i = 0, len = str.length;
	function newParse() {
		var s = waitStr(regTag);
		if(!s) return;
		switch(s) {
			case "{": return findObj();
			case "[": return findArr();
			case "t": return findTrue();
			case "f": return findFalse();
			case "n": return findNull();
			case '"': return findStr();
		}
		return findNum(s);
	}

	function findObj() {
		var obj = new Object;
		while(i < len) {
			var s = waitStr(/\S/);
			if(s == "}") break;
			if(s == ",") continue;
			var key = findStr();
			waitStr(/\:/);
			obj[key] = newParse();
		}
		return obj;
	}

	function findArr() {
		var arr = new Array;
		while(i < len) {
			var s = waitStr(/\S/);
			if(s == "]") break;
			if(s == ",") continue;
			i--; arr.push(newParse());
		}
		return arr;
	}

	function findTrue() { i += 3; return true; }
	function findFalse() { i += 4; return false; }
	function findNull() { i += 3; return null; }

	function findStr() {
		var s = new Array;
		while(i < len) {
			var _s = str.charAt(i++);
			if(_s == '"') break;
			if(_s == "\\") { _s = strDec(str.charAt(i)); i++; }
			s.push(_s);
		}
		return s.join("");
	}

	function findNum(s) {
		while(i < len) {
			var _s = str.charAt(i++);
			if(!/[\d\.\-]/.test(_s)) break;
			s += _s;
		}
		i--; return s - 0;
	}

	function waitStr(reg) {
		while(i < len) {
			var s = str.charAt(i++);
			if(reg.test(s)) return s;
		}
		return "";
	}

	var dic = { n: "\n", r: "\r", b: "\b", f: "\f", t: "\t", v: "\x0b" };
	function strDec(c) {
		switch(c) {
			case "x": i += 2; return unescape("%" + str.substr(i - 2, 2));
			case "u": i += 4; return unescape("%u" + str.substr(i - 4, 4));
		}
		return c in dic ? dic[c] : c;
	}

	return newParse();
};
function GetAppCache() {
	if(Application["AppCache"]) return Application["AppCache"];
	Application["AppCache"] = new Object;
	return Application["AppCache"];
}
DbHelper.Cache = GetAppCache();
%>