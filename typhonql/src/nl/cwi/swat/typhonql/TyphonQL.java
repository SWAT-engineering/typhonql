package nl.cwi.swat.typhonql;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.UnsupportedEncodingException;
import java.net.URI;
import java.net.URISyntaxException;
import java.util.ArrayList;
import java.util.List;

import org.apache.http.HttpEntity;
import org.apache.http.HttpStatus;
import org.apache.http.auth.AuthScope;
import org.apache.http.auth.UsernamePasswordCredentials;
import org.apache.http.client.CredentialsProvider;
import org.apache.http.client.methods.CloseableHttpResponse;
import org.apache.http.client.methods.HttpGet;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.client.utils.URIBuilder;
import org.apache.http.entity.StringEntity;
import org.apache.http.impl.client.BasicCredentialsProvider;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClientBuilder;
import org.bson.BsonArray;
import org.bson.BsonDocument;
import org.bson.BsonInvalidOperationException;
import org.bson.BsonValue;
import org.rascalmpl.interpreter.TypeReifier;
import org.rascalmpl.interpreter.utils.RuntimeExceptionFactory;
import org.rascalmpl.values.ValueFactoryFactory;

import io.usethesource.vallang.IMap;
import io.usethesource.vallang.ISourceLocation;
import io.usethesource.vallang.IString;
import io.usethesource.vallang.IValueFactory;
import nl.cwi.swat.typhonql.workingset.WorkingSet;
import nl.cwi.swat.typhonql.workingset.json.WorkingSetJSON;

public class TyphonQL {

	private final IValueFactory vf;
	private final TypeReifier tr;
		
		
	public TyphonQL(IValueFactory vf) {
		this.vf = vf;
		this.tr = new TypeReifier(vf);
	}
		

	public void bootConnections(ISourceLocation path, IString user, IString password) {
		URI uri = buildUri(path.getURI(), "/api/databases");
		String json = doGet(uri, user.getValue(), password.getValue());
		BsonArray array = BsonArray.parse(json);
		List<ConnectionInfo> infos = new ArrayList<ConnectionInfo>();
		for (BsonValue v : array.getValues()) {
			BsonDocument d = v.asDocument();
			try {
				String engineType = d.getString("engineType").getValue().toLowerCase() + "db";
				DBType dbType = DBType.valueOf(engineType);
				if (dbType == null)
					throw new RuntimeException("Engine type " + d.getString("engineType").getValue() + " not known");
				ConnectionInfo info = new ConnectionInfo(
					path.getURI().toString(),
					d.getString("externalHost").getValue(), 
					d.getNumber("externalPort").intValue(), 
					d.getString("name").getValue(), 
					dbType,
					d.getString("dbType").getValue(),
					d.getString("username").getValue(),
					d.getString("password").getValue());
				infos.add(info);
			} catch (BsonInvalidOperationException e) {
				// TODO not do anything if row of connection information is unparsable
			}
		}
		Connections.boot(infos.toArray(new ConnectionInfo[0]));
	}
	
	public IString readHttpModel(ISourceLocation path, IString user, IString password) {
		URI uri = buildUri(path.getURI(), "/api/models/ml");
		String json = doGet(uri, user.getValue(), password.getValue());
		BsonArray array = BsonArray.parse(json);
		String contents = array.get(0).asDocument().getString("contents").getValue();
		return vf.string(contents);
	}
	
	public void executeResetDatabases(ISourceLocation path, IString user, IString password) {
		URI uri = buildUri(path.getURI(), "/api/resetdatabases");
		doGet(uri, user.getValue(), password.getValue());
	}
	
	public IMap executeQuery(ISourceLocation path, IString user, IString password, IString query) {
		URI uri = buildUri(path.getURI(), "/api/query");
		String json = doPost(uri, user.getValue(), password.getValue(), query.getValue());
		//Document doc = Document.parse(json);
		//String contents = doc.getString("response");
		// TODO this is a workaround
		// The response object does not escape quotes, then it is not parseable
		String contents = json.substring(15,  json.length()-3);
		WorkingSet ws;
		try {
			ws = WorkingSetJSON.fromJSON(new ByteArrayInputStream(contents.getBytes()));
		} catch (IOException e) {
			e.printStackTrace();
			throw RuntimeExceptionFactory.io(vf.string("Problem parsing HTTP response"), null, null);
		}
		return ws.toIValue();
	}
	
	public void executeUpdate(ISourceLocation path, IString user, IString password, IString query) {
		URI uri = buildUri(path.getURI(), "/api/update");
		doPost(uri, user.getValue(), password.getValue(), query.getValue());
	}
	
	private URI buildUri(URI base, String path) {
		URIBuilder builder = new URIBuilder(base);
		builder.setPath(path);
		try {
			return builder.build();
		} catch (URISyntaxException e1) {
			throw new RuntimeException(e1);
		}
	}

	private String doGet(URI path, String user, String password) {
		CredentialsProvider credentialsProvider = new BasicCredentialsProvider();
		credentialsProvider.setCredentials(AuthScope.ANY, new UsernamePasswordCredentials(user, password));
		CloseableHttpClient httpclient = HttpClientBuilder.create().setDefaultCredentialsProvider(credentialsProvider).build();
		HttpGet httpGet = new HttpGet(path);
		
		CloseableHttpResponse response1;
		try {
			response1 = httpclient.execute(httpGet);
		} catch (IOException e1) {
			e1.printStackTrace();
			throw RuntimeExceptionFactory.io(vf.string("Problem executing HTTP request"), null, null);
		} 
		
		if (response1.getStatusLine() != null) {
			if (response1.getStatusLine().getStatusCode() != HttpStatus.SC_OK)
				throw RuntimeExceptionFactory.io(
						vf.string("Problem with the HTTP connection to the polystore: Status was " + response1.getStatusLine().getStatusCode()), null, null);
		}
		
		try {
			HttpEntity entity1 = response1.getEntity();
			ByteArrayOutputStream baos = new ByteArrayOutputStream();
			entity1.writeTo(baos);
			String s = new String(baos.toByteArray());
			return s;

		} catch (IOException e) {
			e.printStackTrace();
			throw RuntimeExceptionFactory.io(vf.string("Problem reading from HTTP resource"), null, null);
		} finally {
			try {
				response1.close();
			} catch (IOException e) {
				e.printStackTrace();
				throw RuntimeExceptionFactory.io(vf.string("Problem closing HTTP resource"), null, null);
			}
		}
	}
	
	private String doPost(URI path, String user, String password, String body) {
		CredentialsProvider credentialsProvider = new BasicCredentialsProvider();
		credentialsProvider.setCredentials(AuthScope.ANY, new UsernamePasswordCredentials(user, password));
		CloseableHttpClient httpclient = HttpClientBuilder.create().setDefaultCredentialsProvider(credentialsProvider).build();
		HttpPost httpPost = new HttpPost(path);
		try {
			httpPost.setEntity(new StringEntity(body));
		} catch (UnsupportedEncodingException e) {
			e.printStackTrace();
			throw RuntimeExceptionFactory.io(vf.string("Problem with encoding of the POST body"), null, null);
		}
		
		CloseableHttpResponse response1;
		try {
			response1 = httpclient.execute(httpPost);

		} catch (IOException e1) {
			e1.printStackTrace();
			throw RuntimeExceptionFactory.io(vf.string("Problem executing HTTP request"), null, null);
		}
		
		if (response1.getStatusLine() != null) {
			if (response1.getStatusLine().getStatusCode() != HttpStatus.SC_OK)
				throw RuntimeExceptionFactory.io(
						vf.string("Problem with the HTTP connection to the polystore: Status was " + response1.getStatusLine().getStatusCode()), null, null);
		}
		
		try {
			HttpEntity entity1 = response1.getEntity();
			ByteArrayOutputStream baos = new ByteArrayOutputStream();
			entity1.writeTo(baos);
			String s = new String(baos.toByteArray());
			return s;

		} catch (IOException e) {
			e.printStackTrace();
			throw RuntimeExceptionFactory.io(vf.string("Problem reading from HTTP resource"), null, null);
		} finally {
			try {
				response1.close();
			} catch (IOException e) {
				e.printStackTrace();
				throw RuntimeExceptionFactory.io(vf.string("Problem closing HTTP resource"), null, null);
			}
		}
	}
	
	public static void main(String[] args) {
		IValueFactory vf = ValueFactoryFactory.getValueFactory();
		TyphonQL ql = new TyphonQL(vf);
		IMap ws = ql.executeQuery(vf.sourceLocation(URI.create("http://localhost:8080")), vf.string("pablo"), vf.string("antonio"), vf.string("from Product p select p"));
		System.out.println(ws);
	}
}
