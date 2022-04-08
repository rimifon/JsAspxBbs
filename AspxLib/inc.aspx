<!-- #include file="core.aspx" --><%
sys.debug = true;
// sys.dbType = "Mono.Data.Sqlite";
sys.dbPath = "|DataDirectory|Sqlite.db";
sys.smtp = { host: "smtp.qq.com", user: "yourqq@qq.com", pass: "" };
sys.wx = { id: "wx6f334128143af949", secret: "1616ab94128494f3f82935cef0acbe94" };
sys.mch = { id: "123456789", key: "1234567890abcdef1234567890abcdef", cert: "/cert/apiclient_cert.p12" };

try { echo(invokeFunc("boot")((env("PATH_INFO").replace(env("SCRIPT_NAME"), "") || "/Index").split("/"))); }
catch(err) { echo(err.message); dbg().trace([ err.message, db().lastSql ]); }
finally { closeAllDb(); dbg().appendLog(); }

function me() {
	var ns = sys.ns + "me";
	var ins = ss(ns).me || new Object;
	if(ins.isLogin) return ins;
	ins.bind = function(user) {
		user.isLogin = true; ss(ns).me = user;
		user.lose = function() { delete ss(ns).me; };
		user.bind = ins.bind; return user;
	};
	ins.lose = new Function;
	return ins;
}

function iswx() { return /MicroMessenger/i.test(env("HTTP_USER_AGENT")); }

function wxlogin(backurl, scope) {
	if(ss().wxinfo) return sys.onwxlogin ? sys.onwxlogin() : redir(backurl);
	ss().wxbackurl = backurl;
	ss().wxbackstate = md5(Math.random(), 16);
	var url = "https://open.weixin.qq.com/connect/oauth2/authorize?appid=" + sys.wx.id;
	url += "&redirect_uri=" + encodeURIComponent("http://" + env("HTTP_HOST") + "/weixin.aspx/GetCode");
	url += "&response_type=code&scope=snsapi_" + (scope || "base") + "&state=" + ss().wxbackstate;
	redir(url);
}

function getopenid(code, state) {
	if(state != ss().wxbackstate && state) return { err: "state 不匹配" };
	var url = "https://api.weixin.qq.com/sns/oauth2/access_token?appid=" + sys.wx.id;
	url += "&secret=" + sys.wx.secret + "&code=" + code + "&grant_type=authorization_code";
	var rs = fromjson(ajax(url));
	if(!rs.openid) return { err: rs.errmsg + ": " + code || "未知错误" };
	return ss().wxinfo = rs;
}

function getwxinfo(res) {
	if(res.scope != "snsapi_userinfo") return { err: "无权获取用户信息" };
	var url = "https://api.weixin.qq.com/sns/userinfo?access_token=" + res.access_token;
	var info = fromjson(ajax( url + "&openid=" + res.openid + "&lang=zh_CN")) || new Object;
	return !info.openid ? { err: info.errmsg || "获取微信资料时出现未知错误" } : info;
}

function wxcashier(fee, apivalue, backurl, goods) {
	if(fee < 1) return { err: "缺少支付费用" };
	if(!me().openid) return { err: "缺少付款人" };
	var par = {
		body: goods || "收银台", attach: apivalue, detail: "{}", total_fee: fee,
		out_trade_no: sys.sTime - 0, openid: me().openid, spbill_create_ip: env("REMOTE_ADDR"),
		notify_url: "http://" + env("HTTP_HOST") + backurl, nonce_str: md5(Math.random(), 16),
		appid: sys.wx.id, mch_id: sys.mch.id, device_info: "WEB", fee_type: "CNY", trade_type: "JSAPI"
	};
	par.sign = wxpaysign(par, sys.mch.key);
	var xml = ajax("https://api.mch.weixin.qq.com/pay/unifiedorder", toxml(par), "text/xml");
	var rs = fromxml(xml);
	if(rs("return_code") == "FAIL") return { err: rs("return_msg") };
	if(!rs("prepay_id")) return { err: rs("err_code_des") };
	var arg = { appId: sys.wx.id, nonceStr: par.nonce_str, signType: "MD5" };
	arg.timeStamp = (sys.sTime - 0 + "").slice(0, -3);
	arg.package = "prepay_id=" + rs("prepay_id");
	arg.paySign = wxpaysign(arg, sys.mch.key);
	return arg;
}

function wxauthpay(apiName) {
	var answer = function(code, msg) { echo(toxml({ return_code: code, return_msg: msg })); };
	var xml = new System.Xml.XmlDocument;
	try { xml.Load(Request.InputStream); }
	catch(err) { return answer("FAIL", err.message); }
	var node = xml.SelectNodes("/xml/*"), par = new Object;
	for(var i = 0; i < node.Count; i++) par[node[i].Name] = node[i].InnerText;
	if(!cc().payLog) cc().payLog = new Array;
	cc().payLog.unshift({ time: sys.sTime.getVarDate(), pay: par });
	if(cc().payLog.length > 100) cc().payLog.length = 100;
	if(!par.sign) return answer("FAIL", "缺少支付签名");
	var sign = par.sign; delete par.sign;
	if(wxpaysign(par, sys.mch.key) != sign) return answer("FAIL", "签名校验失败");
	var rs = db().table("users a").join("wxpaylog b on b.tradewx=@wxid").
		where("a.openid=@openid").select("a.id, b.tradewx").
		fetch({ openid: par.openid, wxid: par.transaction_id });
	if(!rs || rs.tradewx) return answer("SUCCESS", "OK");
	par.sign = sign;
	db().insert("wxpaylog", {
		userid: rs.id, fee: par.total_fee, tradewx: par.transaction_id, apiname: apiName, 
		tradeno: par.out_trade_no, openid: par.openid, memo: tojson(par), apivalue: par.attach
	});
	par.userid = rs.id; par.apivalue = par.attach;
	answer("SUCCESS", "OK"); return par;
}

function wxpaysign(par, mchKey) {
	var arr = new Array;
	for(var x in par) arr.push(x + "=" + par[x]);
	arr.sort(); arr.push("key=" + mchKey);
	return md5(arr.join("&")).ToUpper();
}

// 微信证书请求
function wxcertreq(url, arg) {
	var arrXml = new Array, dic = new Array;
	for(var x in arg) {
		dic.push(x + "=" + arg[x]);
		arrXml.push("<" + x + "><![CDATA[" + arg[x] + "]]></" + x + ">")
	}
	dic.sort(); dic.push("key=" + sys.mch.key);
	arrXml.push("<sign><![CDATA[" + md5(dic.join("&")).toUpperCase() + "]]></sign>");
	var cert = new System.Security.Cryptography.X509Certificates.X509Certificate2(Server.MapPath(sys.mch.cert), sys.mch.id);
	var req : System.Net.HttpWebRequest = System.Net.WebRequest.Create(url);
	req.Method = "POST"; req.ContentType = "text/xml; charset=UTF-8";
	req.ClientCertificates.Add(cert);
	var ipt = req.GetRequestStream();
	var bin = System.Text.Encoding.UTF8.GetBytes("<xml>" + arrXml.join("") + "</xml>");
	ipt.Write(bin, 0, bin.Length); ipt.Close();
	var res = req.GetResponse();
	var xml = new System.Xml.XmlDocument;
	xml.Load(res.GetResponseStream());
	var nodes = xml.SelectNodes("/xml/*");
	var rs = new Object; res.Close();
	for(var i = 0; i < nodes.Count; i++) rs[nodes[i].Name] = nodes[i].InnerText;
	return rs;
}

function wxaccesstoken() {
	return cc("WxAccessToken." + sys.wx.id, function() {
		var url = "https://api.weixin.qq.com/cgi-bin/token?grant_type=client_credential";
		url += "&appid=" + sys.wx.id + "&secret=" + sys.wx.secret;
		var rs = fromjson(ajax(url)) || new Object;
		if(!rs.access_token) dbg().trace("GetAccessToken", rs);
		return rs.access_token;
	}, 7100);
}

// 缓存 jsapi_ticket
function wxjsapiticket() {
	return cc("WxJsApiTicket." + sys.wx.id, function() {
		var url = "https://api.weixin.qq.com/cgi-bin/ticket/getticket?type=jsapi";
		url += "&access_token=" + wxaccesstoken();
		var rs = fromjson(ajax(url)) || new Object;
		if(!rs.ticket) dbg().trace("GetJsApiTicket", rs);
		return rs.ticket;
	}, 7100);
}

// JS API 签名
function wxjsapisign(url) {
	if(!url) return { err: "没有需要签名的网址" };
	if(!sys.wx.id) return { err: "尚未配置 appid" };
	var ticket = wxjsapiticket();
	if(!ticket) return { err: "获取 ticket 失败" };
	var arg = { appId: sys.wx.id, nonceStr: md5(Math.random(), 16), timestamp: (sys.sTime - 0).toString().slice(0, -3) };
	var arr = [ "jsapi_ticket=" + ticket, "noncestr=" + arg.nonceStr, "timestamp=" + arg.timestamp, "url=" + url.split("#")[0] ];
	var sha = new System.Security.Cryptography.SHA1CryptoServiceProvider;
	var bin = System.Text.Encoding.UTF8.GetBytes(arr.join("&"));
	arg.signature = BitConverter.ToString(sha.ComputeHash(bin)).Replace("-", "").ToLower();
	return arg;
}

// 访问监控
function dbg() {
	return sys.dbg || new function() {
		// 已关闭调试功能
		if(!sys.debug) return sys.dbg = { appendLog: function() {}, trace: function() {} };
		// 得到缓存数据
		if(!cc().debug) {
			var last : Array = new Array;
			var slow : Array = new Array;
			var info : Array = new Array;
			cc().debug = { last: last, slow: slow, logs: info };
		}
		var cache = cc().debug, logs = { rows : new Array };	// 调试信息
		this.appendLog = function() {
			var today = sys.sTime.getDate();
			// 访问计数递增
			if(today != cache.date) {
				cache.date = today;
				cache.yesterday = cache.today || 0;
				cache.today = 0;
			}
			cache.today = -~cache.today;
			var route = env("PATH_INFO") || "", url = env("URL"), method = env("REQUEST_METHOD");
			var ip = env("HTTP_X_FORWARDED_FOR") || env("REMOTE_ADDR");
			if(!route.indexOf(url)) route = route.replace(url, "");
			var time = sys.sTime.getVarDate(), exec = new Date - sys.sTime;
			// 方法，路径，路由，IP，访问时间，执行时间
			var row = [ method, url, route, ip, time, exec ];
			// 记录最新日志
			cache.last.unshift(row);
			if(cache.last.length > 100) cache.last.length = 100;
			// 记录调试信息
			if(logs.rows.length) {
				// 方法，路径，路由，时间，时长
				logs.info = [ env("REQUEST_METHOD"), url, route, tojson(sys.sTime.getVarDate()).slice(1, -1), new Date - sys.sTime ];
				cache.logs.unshift(logs);
			}
			if(cache.logs.length > 100) cache.logs.length = 100;
			// 记录慢日志
			var minTime = cache.minTime || 0;
			if(exec < minTime) return;
			cache.slow.push(row);
			cache.slow.sort(function(a, b) { return b[5] - a[5]; });
			if(cache.slow.length > 100) cache.slow.length = 100;
			cache.minTime = cache.slow[ cache.slow.length - 1 ][5];
		};
		this.trace = function(info) {
			var arr = info instanceof Array ? info : [ info ];
			for(var i = 0; i < arr.length; i++) {
				var data = arr[i];
				logs.rows.push([ data instanceof Object ? tojson(data) : data, new Date - sys.sTime ]);
			}
		};
		sys.dbg = this;
	};
}

function invokeFunc(func: String) : Function {
	try{ return eval(func, "unsafe"); }
	catch(err) { return new Function; }
}
%>