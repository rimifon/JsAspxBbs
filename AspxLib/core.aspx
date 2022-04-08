<%@Page Language="Javascript" %><!-- #include file="class.aspx" --><%
// JsAspx v1.2009.26
var sys = { sTime : new Date, db: new Object };
function db(dbPath) {
	if(!dbPath) dbPath = sys.dbPath;
	if(sys.db[dbPath]) return sys.db[dbPath];
	sys.db[dbPath] = new DbHelper(dbPath, sys.dbType || "");
	return sys.db[dbPath];
}

function closeAllDb() { for(var x in sys.db) sys.db[x].close(); }

function cc(k, func, sec) {
	if(!k) return DbHelper.Cache;
	if(!cc().redis) cc().redis = new Object;
	var data = cc().redis[k];
	if(!data) data = cc().redis[k] = new Object;
	if(!sec) sec = 0; sec *= 1000; sec = sys.sTime - sec;
	if(data.time && (data.time > sec)) return data.value;
	data.time = sys.sTime - 0;
	data.value = "function" == typeof func ? func.call(data) : func;
	if(data.value === data.n) delete cc().redis[k];
	return data.value;
}

function ss(ns) {
	var obj = Session[ns || "root"];
	if(!obj) obj = Session[ns || "root"] = new Object;
	return obj;
}

function html(str) { return Server.HtmlEncode(str + ""); }
function form(k) { return enumReq(Request.Form, k, "form"); }
function qstr(k) { return enumReq(Request.QueryString, k, "qstr"); }
function env(k) { return enumReq(Request.ServerVariables, k, "env"); }
function redir(url) { closeAllDb(); Response.Redirect(url, false); }
function btoa(str) { return Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(str)); }
function atob(str) { return System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(str)); }
function echo(str) { Response.Write(str); }
function dump(obj) { echo(tojson(obj)); return obj; }
function tojson(obj) { return DbHelper.tojson(obj); }
function fromjson(str) { return DbHelper.fromjson(str); }
function toxml(obj, ele) {
	var arr = new Array;
	for(var x in obj) {
		if(obj[x] == null) obj[x] += "";
		var tag = isNaN(x) ? x : "item";
		arr.push("object" != typeof obj[x] ? 
			"<" + tag + "><![CDATA[" + obj[x] + "]]></" + tag + ">" :
			toxml(obj[x], tag)
		);
	}
	if(!ele) ele = "xml";
	return "<" + ele + ">" + arr.join("\r\n") + "</" + ele + ">";
}
function fromxml(str: String) {
	var dom = new System.Xml.XmlDocument; dom.LoadXml(str);
	return function(path) { return !path ? str : (dom.SelectSingleNode("//" + path) || {}).InnerText; };
}

function ajax(url, data, contentType) {
	var wc = new System.Net.WebClient;
	wc.Encoding = System.Text.Encoding.UTF8;
	if(!data) return wc.DownloadString(url);
	wc.Headers.Add("Content-Type", contentType || "application/x-www-form-urlencoded");
	if("string" == typeof data) return wc.UploadString(url, data);
	function utf(str) { return encodeURIComponent(str + ""); }
	var arr = new Array;
	for(var x in data) arr.push(utf(x) + "=" + utf(data[x]));
	return wc.UploadString(url, arr.join("&"));
}

function md5(str, len) {
	var csp = new System.Security.Cryptography.MD5CryptoServiceProvider;
	var bin = System.Text.Encoding.UTF8.GetBytes(str);
	bin = csp.ComputeHash(bin);
	str = BitConverter.ToString(bin).Replace("-", "").ToLower();
	return len ? str.substr(Math.round((32 - len) / 2), len) : str;
}

function sendmail(mail, server) {
	var msg = new System.Net.Mail.MailMessage;
	msg.Subject = mail.subject;
	msg.From = new System.Net.Mail.MailAddress(mail.from);
	msg.To.Add(mail.to);
	eachAdd(msg.CC, mail.cc);
	eachAdd(msg.Bcc, mail.bcc);
	msg.Body = mail.body;
	msg.IsBodyHtml = mail.istext ? false : true;
	function eachAdd(addr, arr) {
		if(!arr) return;
		if("string" == typeof arr) arr = [ arr ];
		for(var i = 0; i < arr.length; i++) addr.Add(arr[i]);
	}
	msg.SubjectEncoding = System.Text.Encoding.UTF8;
	msg.BodyEncoding = System.Text.Encoding.UTF8;
	var smtp = new System.Net.Mail.SmtpClient;
	smtp.Host = server.host;
	smtp.Port = server.port || 25;
	if(server.pass) smtp.Credentials = new System.Net.NetworkCredential(server.user, server.pass);
	smtp.EnableSsl = server.ssl ? true : false;
	var str = "OK";
	try{ smtp.Send(msg); }
	catch(ex : System.Net.Mail.SmtpException) { str = ex.Message; }
	return str;
}

function enumReq(req, k, ns) {
	if(k) return req[k];
	if(sys[ns]) return sys[ns];
	var obj = sys[ns] = new Object;
	obj.toString = function() { return tojson(obj); };
	for(var i = 0; i < req.Keys.Count; i++) obj[req.Keys[i]] = req[req.Keys[i]];
	return obj;
}
%>