<!-- #include file="inc.aspx" --><%
// API 文档模式，API 接口编写建议引用此文档
// sys.hideApiFunc = true;	// 文档中不显示源码
// sys.hideApi = true;		// 完全关闭文档显示

// apidoc(api对象，路由数组，禁止自动 json 格式化);
function apidoc(root, route, noFmt) {
	// 跨域判断
	allowCORS(env("HTTP_ORIGIN"));
	if(env("REQUEST_METHOD") == "OPTIONS") return 1;
	if(!route) route = sys.route;
	if(!route) return tojson({ err: "缺少 route 参数" });
	try { var rs = execApi(root, 0); } catch(err) {
	rs = { err: err.message, sql: db().lastSql };
	if(noFmt) throw err; }

	// 执行 Api 
	function execApi(model, dep) {
		var api = (route[-~dep] || "index").toLowerCase();
		if(!model[api]) return api == "index" ? showApi.call(model) : { err: "404 Object not found.", route: route };
		return "function" == typeof model[api] ? model[api]() : execApi(model[api], -~dep);
	}

	// 显示 Api 文档页
	function showApi() {
		if(sys.hideApi) return { err: "404 Object not found." };
		sys.apiPath = env("PATH_INFO").replace(env("URL"), "") || "";
		sys.apiPath = env("URL") + sys.apiPath;
		%><!-- #include file="views/apidoc.html" --><%
	}

	// 跨域处理
	function allowCORS(origin) {
		if(!origin) return;
		Response.AddHeader("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE");
		if(sys.cors) Response.AddHeader("Access-Control-Allow-Headers", sys.cors);
		Response.AddHeader("Access-Control-Allow-Origin", origin);
		Response.AddHeader("Access-Control-Allow-Credentials", "true");
	}
	if(noFmt) return rs;
	return rs instanceof Object ? tojson(rs) : rs;
}
%>