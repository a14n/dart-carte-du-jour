import "dart:io";
import "dart:convert";

import 'package:args/args.dart';
import 'package:logging/logging.dart';

import 'package:dart_carte_du_jour/carte_de_jour.dart';

void main(args) {
  Logger.root.onRecord.listen((LogRecord record) {
    print(record.message);
  });

  Logger.root.finest("args = ${args}");

  // TODO(adam): move arg parsing and command invoking to `unscripted`
  ArgParser parser = _createArgsParser();
  ArgResults results = parser.parse(args);

  if (results['clientConfig'] != null) {
    // TODO: move to parser callback
    String clientConfig = new File(results['clientConfig']).readAsStringSync();
    var data = JSON.decode(clientConfig);
    ClientBuilderConfig clientBuilderConfig =
        new ClientBuilderConfig.fromJson(data);

    startClient(clientBuilderConfig);
    return;
  }

  String dartSdk;
  if (results['sdk'] == null) {
    print("You must provide a value for 'sdk'.");
    _printUsage(parser);
    return;
  } else {
    dartSdk = results['sdk'];
  }

  String configPath;
  if (results['config'] == null) {
    print("You must provide a value for 'config'.");
    _printUsage(parser);
    return;
  } else {
    configPath = results['config'];
  }

  String package = results['package'];
  Version version = new Version.parse(results['version']);
  _initClient(dartSdk, configPath, package, version);
  return;
}

void startClient(ClientBuilderConfig clientBuilderConfig) {
  clientBuilderConfig.packages.forEach((Package package) {
    package.versions.forEach((Version version) {
      buildVersion(package.name, version, clientBuilderConfig);
    });
  });
}

// TODO: move to carte_de_jour.dart
void buildVersion(String packageName,
                 Version version, ClientBuilderConfig clientBuilderConfig) {
  Logger.root.info("Starting build of ${packageName} ${version}");
  Package package = new Package(packageName, [version]);
  String dartSdk = clientBuilderConfig.sdkPath;

  GoogleComputeEngineConfig googleComputeEngineConfig =
      clientBuilderConfig.googleComputeEngineConfig;
  PackageBuildInfoDataStore packageBuildInfoDataStore
      = new PackageBuildInfoDataStore(googleComputeEngineConfig);

  try {
    package.buildDocumentationCacheSync(versionConstraint: version);
    package.initPackageVersion(version);
    package.buildDocumentationSync(version, dartSdk);
    package.moveDocumentationPackages(version);
    package.copyDocumentation(version);
    package.createVersionFile(version);
    package.copyVersionFile(version);
    // Copy the package_build_info.json file, should only be copied if everything
    // else was successful.
    package.createPackageBuildInfo(version, true);
    package.copyPackageBuildInfo(version);

    // TODO: Factor out into Package class
    // all time stamps need to be in UTC/Iso8601 format.
    var now = new DateTime.now().toUtc().toIso8601String();
    PackageBuildInfo packageBuildInfo =
        new PackageBuildInfo(package.name, version, now, true, buildLogStorePath());
    packageBuildInfoDataStore.save(packageBuildInfo).then((r) {
      Logger.root.info("packageBuildInfoDataStore success:${r}");
    });
  } catch (e) {
    Logger.root.severe(("Not able to build ${package.toString()}"));
    package.createPackageBuildInfo(version, false);
    package.copyPackageBuildInfo(version);

    // TODO: Factor out into Package class
    // all time stamps need to be in UTC/Iso8601 format.
    var now = new DateTime.now().toUtc().toIso8601String();
    PackageBuildInfo packageBuildInfo =
        new PackageBuildInfo(package.name, version, now, false, buildLogStorePath());
    packageBuildInfoDataStore.save(packageBuildInfo).then((r) {
      Logger.root.info("packageBuildInfoDataStore failed:${r}");
    });
  }
}

@deprecated
void _initClient(String dartSdk, String configPath, String packageName,
                 Version version) {
  Logger.root.info("Starting build of ${packageName} ${version}");
  Package package = new Package(packageName, [version]);
  String configFile = new File(configPath).readAsStringSync();
  Map config = JSON.decode(configFile);
  String rsaPrivateKey = new File(config["rsaPrivateKey"]).readAsStringSync();
  GoogleComputeEngineConfig googleComputeEngineConfig =
  new GoogleComputeEngineConfig(config["projectId"], config["projectNumber"],
      config["serviceAccountEmail"], rsaPrivateKey);
  PackageBuildInfoDataStore packageBuildInfoDataStore
    = new PackageBuildInfoDataStore(googleComputeEngineConfig);

  try {
    package.buildDocumentationCacheSync(versionConstraint: version);
    package.initPackageVersion(version);
    package.buildDocumentationSync(version, dartSdk);
    package.moveDocumentationPackages(version);
    package.copyDocumentation(version);
    package.createVersionFile(version);
    package.copyVersionFile(version);
    // Copy the package_build_info.json file, should only be copied if everything
    // else was successful.
    package.createPackageBuildInfo(version, true);
    package.copyPackageBuildInfo(version);

    // TODO: Factor out into Package class
    // all time stamps need to be in UTC/Iso8601 format.
    var now = new DateTime.now().toUtc().toIso8601String();
    PackageBuildInfo packageBuildInfo =
        new PackageBuildInfo(package.name, version, now, true, buildLogStorePath());
    packageBuildInfoDataStore.save(packageBuildInfo).then((r) {
      Logger.root.info("packageBuildInfoDataStore = ${r}");
    });
  } catch (e) {
    Logger.root.severe(("Not able to build ${package.toString()}"));
    package.createPackageBuildInfo(version, false);
    package.copyPackageBuildInfo(version);

    // TODO: Factor out into Package class
    // all time stamps need to be in UTC/Iso8601 format.
    var now = new DateTime.now().toUtc().toIso8601String();
    PackageBuildInfo packageBuildInfo =
        new PackageBuildInfo(package.name, version, now, false, buildLogStorePath());
    packageBuildInfoDataStore.save(packageBuildInfo).then((r) {
      Logger.root.info("packageBuildInfoDataStore = ${r}");
    });
  }
}

ArgParser _createArgsParser() {
  ArgParser parser = new ArgParser();
    parser.addFlag('help',
        abbr: 'h',
        negatable: false,
        help: 'show command help',
        callback: (help) {
          if (help) {
            _printUsage(parser);
          }
        });

    parser.addFlag('verbose', abbr: 'v',
        help: 'Output more logging information.', negatable: false,
        callback: (verbose) {
          if (verbose) {
            Logger.root.level = Level.FINEST;
          }
        });

    // TODO: remove when <uuid>.json config is implemented
    parser.addOption(
        'sdk',
        help: 'Path to the sdk. Required.',
        defaultsTo: null);

    // TODO: remove when <uuid>.json config is implemented
    parser.addOption(
        'config',
        help: 'Path to the config. Required.',
        defaultsTo: null);

    // TODO: rename option to `--config`
    parser.addOption(
        'clientConfig',
        help: 'Path to the config. Required.',
        defaultsTo: null);


    //
    // Client options
    //
    parser.addOption(
        'package',
        help: 'Package to generate documentation for.', defaultsTo: null);
    parser.addOption( // TODO(adam): support possible version constraints for package generation.
        'version',
        help: 'Version of package to generate.', defaultsTo: null);

    return parser;
}

void _printUsage(ArgParser parser) {
  print('usage: dart bin/client_builder.dart <options>');
  print('');
  print('where <options> is one or more of:');
  print(parser.getUsage().replaceAll('\n\n', '\n'));
  exit(1);
}