package nl.cwi.swat.typhonql.client;

import static org.rascalmpl.interpreter.utils.ReadEvalPrintDialogMessages.staticErrorMessage;
import static org.rascalmpl.interpreter.utils.ReadEvalPrintDialogMessages.throwMessage;
import static org.rascalmpl.interpreter.utils.ReadEvalPrintDialogMessages.throwableMessage;
import java.io.IOException;
import java.io.PrintWriter;
import java.net.URISyntaxException;
import java.util.List;
import java.util.concurrent.TimeUnit;
import org.rascalmpl.interpreter.Evaluator;
import org.rascalmpl.interpreter.control_exceptions.Throw;
import org.rascalmpl.interpreter.env.GlobalEnvironment;
import org.rascalmpl.interpreter.env.ModuleEnvironment;
import org.rascalmpl.interpreter.load.StandardLibraryContributor;
import org.rascalmpl.interpreter.staticErrors.StaticError;
import org.rascalmpl.library.util.PathConfig;
import org.rascalmpl.uri.URIResolverRegistry;
import org.rascalmpl.uri.URIUtil;
import org.rascalmpl.uri.classloaders.SourceLocationClassLoader;
import org.rascalmpl.uri.project.ProjectURIResolver;
import org.rascalmpl.util.ConcurrentSoftReferenceObjectPool;
import org.rascalmpl.values.ValueFactoryFactory;
import io.usethesource.vallang.ISourceLocation;
import io.usethesource.vallang.IValue;
import io.usethesource.vallang.IValueFactory;
import io.usethesource.vallang.impl.persistent.ValueFactory;
import io.usethesource.vallang.io.StandardTextWriter;
import nl.cwi.swat.typhonql.ConnectionInfo;
import nl.cwi.swat.typhonql.Connections;

/**
 * Thread safe connection to the polystore ql engine, construct this once, and call the executeQuery from as many threads as you like (there is a memory overhead, but it will not interfer with eachother)
 */
public class PolystoreConnection {

	private static final PrintWriter ERROR_WRITER = new PrintWriter(System.err);
	private static final StandardTextWriter VALUE_PRINTER = new StandardTextWriter(true, 2);
	private static String LOCALHOST = "localhost";
	private final PolystoreSchema schema;
	private final ConcurrentSoftReferenceObjectPool<Evaluator> evaluators;
	private static final IValueFactory VF = ValueFactory.getInstance();

	public PolystoreConnection(PolystoreSchema schema, List<DatabaseInfo> infos) throws IOException {
		this.schema = schema;
		// bootstrap the connections
		Connections.boot(infos.stream().map(i -> new ConnectionInfo(LOCALHOST, i)).toArray(ConnectionInfo[]::new));

		// we prepare some configuration that every evaluator will need
		

		URIResolverRegistry reg = URIResolverRegistry.getInstance();
		if (!reg.getRegisteredInputSchemes().contains("project") && !reg.getRegisteredLogicalSchemes().contains("project")) {
			// project URI is not supported, so we have to add support for this (we have to do this only once)
            ISourceLocation projectRoot;
            try {
                projectRoot = URIUtil.createFileLocation(PolystoreConnection.class.getProtectionDomain().getCodeSource().getLocation().getPath());
                if (projectRoot.getPath().endsWith(".jar")) {
                    projectRoot = URIUtil.changePath(URIUtil.changeScheme(projectRoot, "jar+" + projectRoot.getScheme()), projectRoot.getPath() + "!/");
                }
            } catch (URISyntaxException e) {
                throw new RuntimeException("Cannot get to root of the typhonql project", e);
            }
			reg.registerLogical(new ProjectURIResolver(projectRoot, "typhonql"));
			// from now on, |project://typhonql/| should work
		}

		PathConfig pcfg = PathConfig.fromSourceProjectRascalManifest(URIUtil.correctLocation("project", "typhonql", null));
		ClassLoader cl = new SourceLocationClassLoader(pcfg.getClassloaders(), PolystoreConnection.class.getClassLoader());
		
		evaluators = new ConcurrentSoftReferenceObjectPool<>(10, TimeUnit.MINUTES, 2, () -> {
			// we construct a new evaluator for every concurrent call
			GlobalEnvironment  heap = new GlobalEnvironment();
			Evaluator result = new Evaluator(ValueFactoryFactory.getValueFactory(), 
					new PrintWriter(System.err, true), new PrintWriter(System.out, false),
					new ModuleEnvironment("$typhonql$", heap), heap);
			
			result.addRascalSearchPathContributor(StandardLibraryContributor.getInstance());

			for (IValue path : pcfg.getSrcs()) {
				result.addRascalSearchPath((ISourceLocation) path); 
			}
			result.addClassLoader(cl);

			System.out.println("Starting a fresh evaluator to interpret the query (" + Integer.toHexString(System.identityHashCode(result)) + ")");
			System.out.flush();
			// now we are ready to import our main module
			result.doImport(null, "lang::typhonql::Run");
			System.out.println("Finished initializing evaluator: " + Integer.toHexString(System.identityHashCode(result)));
			System.out.flush();
			return result;
		});

	}

	public IValue executeQuery(String query) {
		return evaluators.useAndReturn(evaluator -> {
			try {
                synchronized (evaluator) {
                    // str src, str polystoreId, Schema s,
                    return evaluator.call("run", 
                            ValueFactory.getInstance().string(query),
                            ValueFactory.getInstance().string(LOCALHOST), 
                            schema.asRascalValue());
                }
			}
			catch (StaticError e) {
				staticErrorMessage(ERROR_WRITER,e, VALUE_PRINTER);
				throw e;
			}
			catch (Throw e) {
				throwMessage(ERROR_WRITER,e, VALUE_PRINTER);
				throw e;
			}
			catch (Throwable e) {
				throwableMessage(ERROR_WRITER, e, evaluator.getStackTrace(), VALUE_PRINTER);
				throw e;
			}
		});
	}
}
