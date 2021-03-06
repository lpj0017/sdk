// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/src/dart/analysis/byte_store.dart';
import 'package:analyzer/src/services/available_declarations.dart';
import 'package:analyzer/src/test_utilities/mock_sdk.dart';
import 'package:analyzer/src/test_utilities/resource_provider_mixin.dart';
import 'package:meta/meta.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AvailableDeclarationsTest);
  });
}

class AbstractContextTest with ResourceProviderMixin {
  final byteStore = MemoryByteStore();

  AnalysisContextCollection analysisContextCollection;

  AnalysisContext testAnalysisContext;

  void addDotPackagesDependency(String path, String name, String rootPath) {
    var packagesFile = getFile(path);

    String packagesContent;
    try {
      packagesContent = packagesFile.readAsStringSync();
    } catch (_) {
      packagesContent = '';
    }

    // Ignore if there is already the same package dependency.
    if (packagesContent.contains('$name:file://')) {
      return;
    }

    rootPath = convertPath(rootPath);
    packagesContent += '$name:${toUri('$rootPath/lib')}\n';

    packagesFile.writeAsStringSync(packagesContent);

    createAnalysisContexts();
  }

  void addTestPackageDependency(String name, String rootPath) {
    addDotPackagesDependency('/home/test/.packages', name, rootPath);
  }

  /// Create all analysis contexts in `/home`.
  void createAnalysisContexts() {
    analysisContextCollection = AnalysisContextCollectionImpl(
      includedPaths: [convertPath('/home')],
      resourceProvider: resourceProvider,
      sdkPath: convertPath('/sdk'),
    );

    var testPath = convertPath('/home/test');
    testAnalysisContext = getContext(testPath);
  }

  /// Return the existing analysis context that should be used to analyze the
  /// given [path], or throw [StateError] if the [path] is not analyzed in any
  /// of the created analysis contexts.
  AnalysisContext getContext(String path) {
    path = convertPath(path);
    return analysisContextCollection.contextFor(path);
  }

  setUp() {
    new MockSdk(resourceProvider: resourceProvider);

    newFolder('/home/test');
    newFile('/home/test/.packages', content: '''
test:${toUri('/home/test/lib')}
''');

    createAnalysisContexts();
  }
}

@reflectiveTest
class AvailableDeclarationsTest extends AbstractContextTest {
  DeclarationsTracker tracker;

  final List<LibraryChange> changes = [];

  final Map<int, Library> idToLibrary = {};
  final Map<String, Library> uriToLibrary = {};

  @override
  setUp() {
    super.setUp();
    _createTracker();
  }

  test_changeFile_added_exported() async {
    var a = convertPath('/home/test/lib/a.dart');
    var b = convertPath('/home/test/lib/b.dart');
    var c = convertPath('/home/test/lib/c.dart');
    var d = convertPath('/home/test/lib/d.dart');

    newFile(a, content: r'''
export 'b.dart';
class A {}
''');
    newFile(b, content: r'''
export 'c.dart';
class B {}
''');
    newFile(d, content: r'''
class D {}
''');
    tracker.addContext(testAnalysisContext);

    await _doAllTrackerWork();
    _assertHasLibrary('package:test/a.dart', declarations: [
      _ExpectedDeclaration('A', DeclarationKind.CLASS),
      _ExpectedDeclaration('B', DeclarationKind.CLASS),
    ]);
    _assertHasLibrary('package:test/b.dart', declarations: [
      _ExpectedDeclaration('B', DeclarationKind.CLASS),
    ]);
    _assertHasNoLibrary('package:test/c.dart');
    _assertHasLibrary('package:test/d.dart', declarations: [
      _ExpectedDeclaration('D', DeclarationKind.CLASS),
    ]);

    newFile(c, content: r'''
class C {}
''');
    tracker.changeFile(c);
    await _doAllTrackerWork();

    _assertHasLibrary('package:test/a.dart', declarations: [
      _ExpectedDeclaration('A', DeclarationKind.CLASS),
      _ExpectedDeclaration('B', DeclarationKind.CLASS),
      _ExpectedDeclaration('C', DeclarationKind.CLASS),
    ]);
    _assertHasLibrary('package:test/b.dart', declarations: [
      _ExpectedDeclaration('B', DeclarationKind.CLASS),
      _ExpectedDeclaration('C', DeclarationKind.CLASS),
    ]);
    _assertHasLibrary('package:test/c.dart', declarations: [
      _ExpectedDeclaration('C', DeclarationKind.CLASS),
    ]);
    _assertHasLibrary('package:test/d.dart', declarations: [
      _ExpectedDeclaration('D', DeclarationKind.CLASS),
    ]);
  }

  test_changeFile_added_library() async {
    var a = convertPath('/home/test/lib/a.dart');
    var b = convertPath('/home/test/lib/b.dart');

    newFile(a, content: r'''
class A {}
''');
    tracker.addContext(testAnalysisContext);

    await _doAllTrackerWork();
    _assertHasLibrary('package:test/a.dart', declarations: [
      _ExpectedDeclaration('A', DeclarationKind.CLASS),
    ]);
    _assertHasNoLibrary('package:test/b.dart');

    newFile(b, content: r'''
class B {}
''');
    tracker.changeFile(b);
    await _doAllTrackerWork();

    _assertHasLibrary('package:test/a.dart', declarations: [
      _ExpectedDeclaration('A', DeclarationKind.CLASS),
    ]);
    _assertHasLibrary('package:test/b.dart', declarations: [
      _ExpectedDeclaration('B', DeclarationKind.CLASS),
    ]);
  }

  test_changeFile_added_part() async {
    var a = convertPath('/home/test/lib/a.dart');
    var b = convertPath('/home/test/lib/b.dart');
    var c = convertPath('/home/test/lib/c.dart');

    newFile(a, content: r'''
part 'b.dart';
class A {}
''');
    newFile(c, content: r'''
class C {}
''');
    tracker.addContext(testAnalysisContext);

    await _doAllTrackerWork();
    _assertHasLibrary('package:test/a.dart', declarations: [
      _ExpectedDeclaration('A', DeclarationKind.CLASS),
    ]);
    _assertHasNoLibrary('package:test/b.dart');
    _assertHasLibrary('package:test/c.dart', declarations: [
      _ExpectedDeclaration('C', DeclarationKind.CLASS),
    ]);

    newFile(b, content: r'''
part of 'a.dart';
class B {}
''');
    tracker.changeFile(b);
    await _doAllTrackerWork();

    _assertHasLibrary('package:test/a.dart', declarations: [
      _ExpectedDeclaration('A', DeclarationKind.CLASS),
      _ExpectedDeclaration('B', DeclarationKind.CLASS),
    ]);
    _assertHasNoLibrary('package:test/b.dart');
    _assertHasLibrary('package:test/c.dart', declarations: [
      _ExpectedDeclaration('C', DeclarationKind.CLASS),
    ]);
  }

  test_changeFile_deleted_exported() async {
    var a = convertPath('/home/test/lib/a.dart');
    var b = convertPath('/home/test/lib/b.dart');
    var c = convertPath('/home/test/lib/c.dart');
    var d = convertPath('/home/test/lib/d.dart');

    newFile(a, content: r'''
export 'b.dart';
class A {}
''');
    newFile(b, content: r'''
export 'c.dart';
class B {}
''');
    newFile(c, content: r'''
class C {}
''');
    newFile(d, content: r'''
class D {}
''');
    tracker.addContext(testAnalysisContext);

    await _doAllTrackerWork();
    _assertHasLibrary('package:test/a.dart', declarations: [
      _ExpectedDeclaration('A', DeclarationKind.CLASS),
      _ExpectedDeclaration('B', DeclarationKind.CLASS),
      _ExpectedDeclaration('C', DeclarationKind.CLASS),
    ]);
    _assertHasLibrary('package:test/b.dart', declarations: [
      _ExpectedDeclaration('B', DeclarationKind.CLASS),
      _ExpectedDeclaration('C', DeclarationKind.CLASS),
    ]);
    _assertHasLibrary('package:test/c.dart', declarations: [
      _ExpectedDeclaration('C', DeclarationKind.CLASS),
    ]);
    _assertHasLibrary('package:test/d.dart', declarations: [
      _ExpectedDeclaration('D', DeclarationKind.CLASS),
    ]);

    deleteFile(c);
    tracker.changeFile(c);
    await _doAllTrackerWork();

    _assertHasLibrary('package:test/a.dart', declarations: [
      _ExpectedDeclaration('A', DeclarationKind.CLASS),
      _ExpectedDeclaration('B', DeclarationKind.CLASS),
    ]);
    _assertHasLibrary('package:test/b.dart', declarations: [
      _ExpectedDeclaration('B', DeclarationKind.CLASS),
    ]);
    _assertHasNoLibrary('package:test/c.dart');
    _assertHasLibrary('package:test/d.dart', declarations: [
      _ExpectedDeclaration('D', DeclarationKind.CLASS),
    ]);
  }

  test_changeFile_deleted_library() async {
    var a = convertPath('/home/test/lib/a.dart');
    var b = convertPath('/home/test/lib/b.dart');

    newFile(a, content: '');
    newFile(b, content: '');
    tracker.addContext(testAnalysisContext);

    await _doAllTrackerWork();
    _assertHasLibrary('package:test/a.dart');
    _assertHasLibrary('package:test/b.dart');

    deleteFile(a);
    tracker.changeFile(a);
    await _doAllTrackerWork();

    _assertHasNoLibrary('package:test/a.dart');
    _assertHasLibrary('package:test/b.dart');
  }

  test_changeFile_deleted_part() async {
    var a = convertPath('/home/test/lib/a.dart');
    var b = convertPath('/home/test/lib/b.dart');
    var c = convertPath('/home/test/lib/c.dart');

    newFile(a, content: r'''
part 'b.dart';
class A {}
''');
    newFile(b, content: r'''
part of 'a.dart';
class B {}
''');
    newFile(c, content: r'''
class C {}
''');
    tracker.addContext(testAnalysisContext);

    await _doAllTrackerWork();
    _assertHasLibrary('package:test/a.dart', declarations: [
      _ExpectedDeclaration('A', DeclarationKind.CLASS),
      _ExpectedDeclaration('B', DeclarationKind.CLASS),
    ]);
    _assertHasLibrary('package:test/c.dart', declarations: [
      _ExpectedDeclaration('C', DeclarationKind.CLASS),
    ]);

    deleteFile(b);
    tracker.changeFile(b);
    await _doAllTrackerWork();

    _assertHasLibrary('package:test/a.dart', declarations: [
      _ExpectedDeclaration('A', DeclarationKind.CLASS),
    ]);
    _assertHasLibrary('package:test/c.dart', declarations: [
      _ExpectedDeclaration('C', DeclarationKind.CLASS),
    ]);
  }

  test_changeFile_updated_exported() async {
    var a = convertPath('/home/test/lib/a.dart');
    var b = convertPath('/home/test/lib/b.dart');
    var c = convertPath('/home/test/lib/c.dart');
    var d = convertPath('/home/test/lib/d.dart');

    newFile(a, content: r'''
export 'b.dart';
class A {}
''');
    newFile(b, content: r'''
export 'c.dart';
class B {}
''');
    newFile(c, content: r'''
class C {}
''');
    newFile(d, content: r'''
class D {}
''');
    tracker.addContext(testAnalysisContext);

    await _doAllTrackerWork();
    _assertHasLibrary('package:test/a.dart', declarations: [
      _ExpectedDeclaration('A', DeclarationKind.CLASS),
      _ExpectedDeclaration('B', DeclarationKind.CLASS),
      _ExpectedDeclaration('C', DeclarationKind.CLASS),
    ]);
    _assertHasLibrary('package:test/b.dart', declarations: [
      _ExpectedDeclaration('B', DeclarationKind.CLASS),
      _ExpectedDeclaration('C', DeclarationKind.CLASS),
    ]);
    _assertHasLibrary('package:test/c.dart', declarations: [
      _ExpectedDeclaration('C', DeclarationKind.CLASS),
    ]);
    _assertHasLibrary('package:test/d.dart', declarations: [
      _ExpectedDeclaration('D', DeclarationKind.CLASS),
    ]);

    newFile(c, content: r'''
class C2 {}
''');
    tracker.changeFile(c);
    await _doAllTrackerWork();

    _assertHasLibrary('package:test/a.dart', declarations: [
      _ExpectedDeclaration('A', DeclarationKind.CLASS),
      _ExpectedDeclaration('B', DeclarationKind.CLASS),
      _ExpectedDeclaration('C2', DeclarationKind.CLASS),
    ]);
    _assertHasLibrary('package:test/b.dart', declarations: [
      _ExpectedDeclaration('B', DeclarationKind.CLASS),
      _ExpectedDeclaration('C2', DeclarationKind.CLASS),
    ]);
    _assertHasLibrary('package:test/c.dart', declarations: [
      _ExpectedDeclaration('C2', DeclarationKind.CLASS),
    ]);
    _assertHasLibrary('package:test/d.dart', declarations: [
      _ExpectedDeclaration('D', DeclarationKind.CLASS),
    ]);
  }

  test_changeFile_updated_library() async {
    var a = convertPath('/home/test/lib/a.dart');
    var b = convertPath('/home/test/lib/b.dart');

    newFile(a, content: r'''
class A {}
''');
    newFile(b, content: r'''
class B {}
''');
    tracker.addContext(testAnalysisContext);

    await _doAllTrackerWork();
    _assertHasLibrary('package:test/a.dart', declarations: [
      _ExpectedDeclaration('A', DeclarationKind.CLASS),
    ]);
    _assertHasLibrary('package:test/b.dart', declarations: [
      _ExpectedDeclaration('B', DeclarationKind.CLASS),
    ]);

    newFile(a, content: r'''
class A2 {}
''');
    tracker.changeFile(a);
    await _doAllTrackerWork();

    _assertHasLibrary('package:test/a.dart', declarations: [
      _ExpectedDeclaration('A2', DeclarationKind.CLASS),
    ]);
    _assertHasLibrary('package:test/b.dart', declarations: [
      _ExpectedDeclaration('B', DeclarationKind.CLASS),
    ]);
  }

  test_changeFile_updated_part() async {
    var a = convertPath('/home/test/lib/a.dart');
    var b = convertPath('/home/test/lib/b.dart');
    var c = convertPath('/home/test/lib/c.dart');

    newFile(a, content: r'''
part 'b.dart';
class A {}
''');
    newFile(b, content: r'''
part of 'a.dart';
class B {}
''');
    newFile(c, content: r'''
class C {}
''');
    tracker.addContext(testAnalysisContext);

    await _doAllTrackerWork();
    _assertHasLibrary('package:test/a.dart', declarations: [
      _ExpectedDeclaration('A', DeclarationKind.CLASS),
      _ExpectedDeclaration('B', DeclarationKind.CLASS),
    ]);
    _assertHasLibrary('package:test/c.dart', declarations: [
      _ExpectedDeclaration('C', DeclarationKind.CLASS),
    ]);

    newFile(b, content: r'''
part of 'a.dart';
class B2 {}
''');
    tracker.changeFile(b);
    await _doAllTrackerWork();

    _assertHasLibrary('package:test/a.dart', declarations: [
      _ExpectedDeclaration('A', DeclarationKind.CLASS),
      _ExpectedDeclaration('B2', DeclarationKind.CLASS),
    ]);
    _assertHasLibrary('package:test/c.dart', declarations: [
      _ExpectedDeclaration('C', DeclarationKind.CLASS),
    ]);
  }

  test_changesStream_noDuplicates() async {
    newFile('/home/aaa/lib/a.dart', content: 'class A {}');

    newFile('/home/bbb/pubspec.yaml', content: r'''
dependencies:
  aaa: any
''');
    addDotPackagesDependency('/home/bbb/.packages', 'aaa', '/home/aaa');
    newFile('/home/bbb/lib/b.dart', content: 'class B {}');

    newFile('/home/ccc/pubspec.yaml', content: r'''
dependencies:
  aaa: any
''');
    addDotPackagesDependency('/home/ccc/.packages', 'aaa', '/home/aaa');
    newFile('/home/ccc/lib/c.dart', content: 'class C {}');

    createAnalysisContexts();

    var bPath = convertPath('/home/bbb');
    var cPath = convertPath('/home/ccc');

    var bAnalysisContext = analysisContextCollection.contextFor(bPath);
    var cAnalysisContext = analysisContextCollection.contextFor(cPath);

    tracker.addContext(bAnalysisContext);
    tracker.addContext(cAnalysisContext);
    await _doAllTrackerWork();

    var uniquePathSet = Set<String>();
    for (var change in changes) {
      for (var library in change.changed) {
        if (!uniquePathSet.add(library.path)) {
          fail('Not unique path: ${library.path}');
        }
      }
    }
  }

  test_export() async {
    newFile('/home/test/lib/a.dart', content: r'''
class A {}
class B {}
''');
    newFile('/home/test/lib/test.dart', content: r'''
export 'a.dart';
class C {}
''');
    tracker.addContext(testAnalysisContext);

    await _doAllTrackerWork();
    _assertHasLibrary('package:test/test.dart', declarations: [
      _ExpectedDeclaration.class_('A'),
      _ExpectedDeclaration.class_('B'),
      _ExpectedDeclaration.class_('C'),
    ]);
  }

  test_export_combinators_hide() async {
    newFile('/home/test/lib/a.dart', content: r'''
class A {}
class B {}
class C {}
''');
    newFile('/home/test/lib/test.dart', content: r'''
export 'a.dart' hide B;
class D {}
''');
    tracker.addContext(testAnalysisContext);

    await _doAllTrackerWork();
    _assertHasLibrary('package:test/test.dart', declarations: [
      _ExpectedDeclaration.class_('A'),
      _ExpectedDeclaration.class_('C'),
      _ExpectedDeclaration.class_('D'),
    ]);
  }

  test_export_combinators_show() async {
    newFile('/home/test/lib/a.dart', content: r'''
class A {}
class B {}
class C {}
''');
    newFile('/home/test/lib/test.dart', content: r'''
export 'a.dart' show B;
class D {}
''');
    tracker.addContext(testAnalysisContext);

    await _doAllTrackerWork();
    _assertHasLibrary('package:test/test.dart', declarations: [
      _ExpectedDeclaration.class_('B'),
      _ExpectedDeclaration.class_('D'),
    ]);
  }

  test_export_cycle() async {
    newFile('/home/test/lib/a.dart', content: r'''
export 'b.dart';
class A {}
''');
    newFile('/home/test/lib/b.dart', content: r'''
export 'a.dart';
class B {}
''');
    newFile('/home/test/lib/test.dart', content: r'''
export 'b.dart';
class C {}
''');
    tracker.addContext(testAnalysisContext);

    await _doAllTrackerWork();

    _assertHasLibrary('package:test/a.dart', declarations: [
      _ExpectedDeclaration.class_('A'),
      _ExpectedDeclaration.class_('B'),
    ]);

    _assertHasLibrary('package:test/b.dart', declarations: [
      _ExpectedDeclaration.class_('A'),
      _ExpectedDeclaration.class_('B'),
    ]);

    _assertHasLibrary('package:test/test.dart', declarations: [
      _ExpectedDeclaration.class_('A'),
      _ExpectedDeclaration.class_('B'),
      _ExpectedDeclaration.class_('C'),
    ]);
  }

  test_export_missing() async {
    newFile('/home/test/lib/test.dart', content: r'''
export 'a.dart';
class C {}
''');
    tracker.addContext(testAnalysisContext);

    await _doAllTrackerWork();
    _assertHasLibrary('package:test/test.dart', declarations: [
      _ExpectedDeclaration.class_('C'),
    ]);
  }

  test_export_sequence() async {
    newFile('/home/test/lib/a.dart', content: r'''
class A {}
''');
    newFile('/home/test/lib/b.dart', content: r'''
export 'a.dart';
class B {}
''');
    newFile('/home/test/lib/test.dart', content: r'''
export 'b.dart';
class C {}
''');
    tracker.addContext(testAnalysisContext);

    await _doAllTrackerWork();

    _assertHasLibrary('package:test/a.dart', declarations: [
      _ExpectedDeclaration.class_('A'),
    ]);

    _assertHasLibrary('package:test/b.dart', declarations: [
      _ExpectedDeclaration.class_('A'),
      _ExpectedDeclaration.class_('B'),
    ]);

    _assertHasLibrary('package:test/test.dart', declarations: [
      _ExpectedDeclaration.class_('A'),
      _ExpectedDeclaration.class_('B'),
      _ExpectedDeclaration.class_('C'),
    ]);
  }

  test_export_shadowedByLocal() async {
    newFile('/home/test/lib/a.dart', content: r'''
class A {}
class B {}
''');
    newFile('/home/test/lib/test.dart', content: r'''
export 'a.dart';

mixin B {}
''');
    tracker.addContext(testAnalysisContext);

    await _doAllTrackerWork();
    _assertHasLibrary('package:test/test.dart', declarations: [
      _ExpectedDeclaration.class_('A'),
      _ExpectedDeclaration.mixin('B'),
    ]);
  }

  test_getContext() async {
    newFile('/home/test/lib/a.dart', content: r'''
class A {}
class B {}
''');
    var addContext = tracker.addContext(testAnalysisContext);
    expect(tracker.getContext(testAnalysisContext), same(addContext));
  }

  test_getLibraries_bazel() async {
    newFile('/home/aaa/lib/a.dart', content: 'class A {}');
    newFile('/home/aaa/lib/src/a2.dart', content: 'class A2 {}');

    newFile('/home/bbb/lib/b.dart', content: 'class B {}');
    newFile('/home/bbb/lib/src/b2.dart', content: 'class B2 {}');

    newFile('/home/material_button/BUILD', content: '');
    newFile(
      '/home/material_button/lib/button.dart',
      content: 'class MaterialButton {}',
    );
    newFile(
      '/home/material_button/test/button_test.dart',
      content: 'class MaterialButtonTest {}',
    );

    newFile('/home/material_button/testing/BUILD', content: '');
    newFile(
      '/home/material_button/testing/lib/material_button_po.dart',
      content: 'class MaterialButtonPO {}',
    );

    var packagesFilePath = '/home/material_button/.packages';
    addDotPackagesDependency(packagesFilePath, 'aaa', '/home/aaa');
    addDotPackagesDependency(packagesFilePath, 'bbb', '/home/bbb');
    addDotPackagesDependency(
      packagesFilePath,
      'material_button',
      '/home/material_button',
    );
    addDotPackagesDependency(
      packagesFilePath,
      'material_button_testing',
      '/home/material_button/testing',
    );

    var analysisContext = analysisContextCollection.contextFor(
      convertPath('/home/material_button'),
    );
    var context = tracker.addContext(analysisContext);
    context.setDependencies({
      convertPath('/home/material_button'): [convertPath('/home/aaa/lib')],
      convertPath('/home/material_button/testing'): [
        convertPath('/home/bbb/lib'),
        convertPath('/home/material_button/lib'),
      ],
    });
    await _doAllTrackerWork();

    _assertHasLibrary('package:aaa/a.dart', declarations: [
      _ExpectedDeclaration.class_('A'),
    ]);
    _assertHasNoLibrary('package:aaa/src/a2.dart');

    _assertHasLibrary('package:bbb/b.dart', declarations: [
      _ExpectedDeclaration.class_('B'),
    ]);
    _assertHasNoLibrary('package:bbb/src/b2.dart');

    _assertHasLibrary('package:material_button/button.dart', declarations: [
      _ExpectedDeclaration.class_('MaterialButton'),
    ]);
    _assertHasLibrary(
      toUri('/home/material_button/test/button_test.dart').toString(),
      declarations: [
        _ExpectedDeclaration.class_('MaterialButtonTest'),
      ],
    );
    _assertHasLibrary(
      'package:material_button_testing/material_button_po.dart',
      declarations: [
        _ExpectedDeclaration.class_('MaterialButtonPO'),
      ],
    );

    {
      var path = convertPath('/home/material_button/lib/_.dart');
      var libraries = context.getLibraries(path);
      _assertHasLibraries(
        libraries.sdk,
        uriList: ['dart:core', 'dart:async'],
      );
      _assertHasLibraries(
        libraries.dependencies,
        uriList: ['package:aaa/a.dart'],
        only: true,
      );
      _assertHasLibraries(
        libraries.context,
        uriList: [
          'package:material_button/button.dart',
        ],
        only: true,
      );
    }

    {
      var path = convertPath('/home/material_button/test/_.dart');
      var libraries = context.getLibraries(path);
      _assertHasLibraries(
        libraries.sdk,
        uriList: ['dart:core', 'dart:async'],
      );
      _assertHasLibraries(
        libraries.dependencies,
        uriList: ['package:aaa/a.dart'],
        only: true,
      );
      _assertHasLibraries(
        libraries.context,
        uriList: [
          'package:material_button/button.dart',
          toUri('/home/material_button/test/button_test.dart').toString(),
        ],
        only: true,
      );
    }

    {
      var path = convertPath('/home/material_button/testing/lib/_.dart');
      var libraries = context.getLibraries(path);
      _assertHasLibraries(
        libraries.sdk,
        uriList: ['dart:core', 'dart:async'],
      );
      _assertHasLibraries(
        libraries.dependencies,
        uriList: [
          'package:bbb/b.dart',
          'package:material_button/button.dart',
        ],
        only: true,
      );
      _assertHasLibraries(
        libraries.context,
        uriList: [
          'package:material_button_testing/material_button_po.dart',
        ],
        only: true,
      );
    }
  }

  test_getLibraries_pub() async {
    newFile('/home/aaa/lib/a.dart', content: 'class A {}');
    newFile('/home/aaa/lib/src/a2.dart', content: 'class A2 {}');

    newFile('/home/bbb/lib/b.dart', content: 'class B {}');
    newFile('/home/bbb/lib/src/b2.dart', content: 'class B2 {}');

    newFile('/home/ccc/lib/c.dart', content: 'class C {}');
    newFile('/home/ccc/lib/src/c2.dart', content: 'class C2 {}');

    newFile('/home/test/pubspec.yaml', content: r'''
name: test
dependencies:
  aaa: any
dev_dependencies:
  bbb: any
''');
    newFile('/home/test/lib/t.dart', content: 'class T {}');
    newFile('/home/test/lib/src/t2.dart', content: 'class T2 {}');
    newFile('/home/test/bin/t3.dart', content: 'class T3 {}');
    newFile('/home/test/test/t4.dart', content: 'class T4 {}');

    newFile('/home/test/samples/basic/pubspec.yaml', content: r'''
name: test
dependencies:
  ccc: any
  test: any
''');
    newFile('/home/test/samples/basic/lib/s.dart', content: 'class S {}');

    addTestPackageDependency('aaa', '/home/aaa');
    addTestPackageDependency('bbb', '/home/bbb');
    addTestPackageDependency('ccc', '/home/ccc');
    addTestPackageDependency('basic', '/home/test/samples/basic');

    var context = tracker.addContext(testAnalysisContext);
    await _doAllTrackerWork();

    _assertHasLibrary('package:aaa/a.dart', declarations: [
      _ExpectedDeclaration.class_('A'),
    ]);
    _assertHasNoLibrary('package:aaa/src/a2.dart');

    _assertHasLibrary('package:bbb/b.dart', declarations: [
      _ExpectedDeclaration.class_('B'),
    ]);
    _assertHasNoLibrary('package:bbb/src/b2.dart');

    _assertHasLibrary('package:ccc/c.dart', declarations: [
      _ExpectedDeclaration.class_('C'),
    ]);
    _assertHasNoLibrary('package:ccc/src/c2.dart');

    _assertHasLibrary('package:test/t.dart', declarations: [
      _ExpectedDeclaration.class_('T'),
    ]);
    _assertHasLibrary('package:test/src/t2.dart', declarations: [
      _ExpectedDeclaration.class_('T2'),
    ]);

    _assertHasLibrary('package:basic/s.dart', declarations: [
      _ExpectedDeclaration.class_('S'),
    ]);

    {
      var path = convertPath('/home/test/lib/_.dart');
      var libraries = context.getLibraries(path);
      _assertHasLibraries(
        libraries.sdk,
        uriList: ['dart:core', 'dart:async'],
      );
      _assertHasLibraries(
        libraries.dependencies,
        uriList: ['package:aaa/a.dart'],
        only: true,
      );
      // Note, no `bin/` or `test/` libraries.
      // Note, has `lib/src` library.
      _assertHasLibraries(
        libraries.context,
        uriList: [
          'package:test/t.dart',
          'package:test/src/t2.dart',
        ],
        only: true,
      );
    }

    {
      var path = convertPath('/home/test/bin/_.dart');
      var libraries = context.getLibraries(path);
      _assertHasLibraries(
        libraries.sdk,
        uriList: ['dart:core', 'dart:async'],
      );
      _assertHasLibraries(
        libraries.dependencies,
        uriList: [
          'package:aaa/a.dart',
          'package:bbb/b.dart',
        ],
        only: true,
      );
      // Note, no `test/` libraries.
      _assertHasLibraries(
        libraries.context,
        uriList: [
          'package:test/t.dart',
          'package:test/src/t2.dart',
          toUri('/home/test/bin/t3.dart').toString(),
        ],
        only: true,
      );
    }

    {
      var path = convertPath('/home/test/test/_.dart');
      var libraries = context.getLibraries(path);
      _assertHasLibraries(
        libraries.sdk,
        uriList: ['dart:core', 'dart:async'],
      );
      _assertHasLibraries(
        libraries.dependencies,
        uriList: [
          'package:aaa/a.dart',
          'package:bbb/b.dart',
        ],
        only: true,
      );
      // Note, no `bin/` libraries.
      _assertHasLibraries(
        libraries.context,
        uriList: [
          'package:test/t.dart',
          'package:test/src/t2.dart',
          toUri('/home/test/test/t4.dart').toString(),
        ],
        only: true,
      );
    }

    {
      var path = convertPath('/home/test/samples/basic/lib/_.dart');
      var libraries = context.getLibraries(path);
      _assertHasLibraries(
        libraries.sdk,
        uriList: ['dart:core', 'dart:async'],
      );
      _assertHasLibraries(
        libraries.dependencies,
        uriList: [
          'package:ccc/c.dart',
          'package:test/t.dart',
        ],
        only: true,
      );
      // Note, no `package:test` libraries.
      _assertHasLibraries(
        libraries.context,
        uriList: [
          'package:basic/s.dart',
        ],
        only: true,
      );
    }
  }

  test_getLibraries_setDependencies() async {
    newFile('/home/aaa/lib/a.dart', content: r'''
export 'src/a2.dart' show A2;
class A1 {}
''');
    newFile('/home/aaa/lib/src/a2.dart', content: r'''
class A2 {}
class A3 {}
''');
    newFile('/home/bbb/lib/b.dart', content: r'''
class B {}
''');

    addTestPackageDependency('aaa', '/home/aaa');
    addTestPackageDependency('bbb', '/home/bbb');

    newFile('/home/test/lib/t.dart', content: 'class T {}');
    newFile('/home/test/lib/src/t2.dart', content: 'class T2 {}');
    newFile('/home/test/test/t3.dart', content: 'class T3 {}');

    var context = tracker.addContext(testAnalysisContext);
    context.setDependencies({
      convertPath('/home/test'): [
        convertPath('/home/aaa/lib'),
        convertPath('/home/bbb/lib'),
      ],
      convertPath('/home/test/lib'): [convertPath('/home/aaa/lib')],
    });

    await _doAllTrackerWork();

    _assertHasLibrary('package:aaa/a.dart', declarations: [
      _ExpectedDeclaration.class_('A1'),
      _ExpectedDeclaration.class_('A2'),
    ]);
    _assertHasNoLibrary('package:aaa/src/a2.dart');
    _assertHasLibrary('package:bbb/b.dart', declarations: [
      _ExpectedDeclaration.class_('B'),
    ]);
    _assertHasLibrary('package:test/t.dart', declarations: [
      _ExpectedDeclaration.class_('T'),
    ]);
    _assertHasLibrary('package:test/src/t2.dart', declarations: [
      _ExpectedDeclaration.class_('T2'),
    ]);
    _assertHasLibrary(
      toUri('/home/test/test/t3.dart').toString(),
      declarations: [
        _ExpectedDeclaration.class_('T3'),
      ],
    );

    // `lib/` is configured to see `package:aaa`.
    {
      var path = convertPath('/home/test/lib/_.dart');
      var libraries = context.getLibraries(path);
      _assertHasLibraries(
        libraries.dependencies,
        uriList: ['package:aaa/a.dart'],
        only: true,
      );
      // Not in a package, so all context files are visible.
      _assertHasLibraries(
        libraries.context,
        uriList: [
          'package:test/t.dart',
          'package:test/src/t2.dart',
          toUri('/home/test/test/t3.dart').toString(),
        ],
        only: true,
      );
    }

    // `test/` is configured to see `package:aaa` and `package:bbb`.
    {
      var path = convertPath('/home/test/bin/_.dart');
      var libraries = context.getLibraries(path);
      _assertHasLibraries(
        libraries.dependencies,
        uriList: [
          'package:aaa/a.dart',
          'package:bbb/b.dart',
        ],
        only: true,
      );
      // Not in a package, so all context files are visible.
      _assertHasLibraries(
        libraries.context,
        uriList: [
          'package:test/t.dart',
          'package:test/src/t2.dart',
          toUri('/home/test/test/t3.dart').toString(),
        ],
        only: true,
      );
    }
  }

  test_getLibraries_setDependencies_twice() async {
    newFile('/home/aaa/lib/a.dart', content: r'''
class A {}
''');
    newFile('/home/bbb/lib/b.dart', content: r'''
class B {}
''');

    addTestPackageDependency('aaa', '/home/aaa');
    addTestPackageDependency('bbb', '/home/bbb');

    newFile('/home/test/lib/test.dart', content: r'''
class C {}
''');

    var context = tracker.addContext(testAnalysisContext);

    var aUri = 'package:aaa/a.dart';
    var bUri = 'package:bbb/b.dart';

    context.setDependencies({
      convertPath('/home/test'): [convertPath('/home/aaa/lib')],
    });
    await _doAllTrackerWork();

    _assertHasLibrary(aUri, declarations: [
      _ExpectedDeclaration.class_('A'),
    ]);
    _assertHasNoLibrary(bUri);

    // The package can see package:aaa, but not package:bbb
    {
      var path = convertPath('/home/test/lib/a.dart');
      var libraries = context.getLibraries(path);
      _assertHasLibraries(
        libraries.dependencies,
        uriList: ['package:aaa/a.dart'],
        only: true,
      );
    }

    context.setDependencies({
      convertPath('/home/test'): [convertPath('/home/bbb/lib')],
    });
    await _doAllTrackerWork();

    _assertHasLibrary(aUri, declarations: [
      _ExpectedDeclaration.class_('A'),
    ]);
    _assertHasLibrary(bUri, declarations: [
      _ExpectedDeclaration.class_('B'),
    ]);

    // The package can see package:bbb, but not package:aaa
    {
      var path = convertPath('/home/test/lib/a.dart');
      var libraries = context.getLibraries(path);
      _assertHasLibraries(
        libraries.dependencies,
        uriList: ['package:bbb/b.dart'],
        only: true,
      );
    }
  }

  test_kindsOfDeclarations() async {
    newFile('/home/test/lib/test.dart', content: r'''
class MyClass {}
class MyClassTypeAlias = Object with MyMixin;
enum MyEnum {a, b, c}
void myFunction() {}
typedef MyFunctionTypeAlias = void Function();
mixin MyMixin {}
var myVariable1, myVariable2;
''');
    tracker.addContext(testAnalysisContext);

    await _doAllTrackerWork();
    _assertHasLibrary('package:test/test.dart', declarations: [
      _ExpectedDeclaration.class_('MyClass'),
      _ExpectedDeclaration.classTypeAlias('MyClassTypeAlias'),
      _ExpectedDeclaration.enum_('MyEnum'),
      _ExpectedDeclaration.function('myFunction'),
      _ExpectedDeclaration.functionTypeAlias('MyFunctionTypeAlias'),
      _ExpectedDeclaration.mixin('MyMixin'),
      _ExpectedDeclaration.variable('myVariable1'),
      _ExpectedDeclaration.variable('myVariable2'),
    ]);
  }

  test_parts() async {
    newFile('/home/test/lib/a.dart', content: r'''
part of 'test.dart';
class A {}
''');
    newFile('/home/test/lib/b.dart', content: r'''
part of 'test.dart';
class B {}
''');
    newFile('/home/test/lib/test.dart', content: r'''
part 'a.dart';
part 'b.dart';
class C {}
''');
    tracker.addContext(testAnalysisContext);

    await _doAllTrackerWork();
    _assertHasLibrary('package:test/test.dart', declarations: [
      _ExpectedDeclaration.class_('A'),
      _ExpectedDeclaration.class_('B'),
      _ExpectedDeclaration.class_('C'),
    ]);
  }

  test_publicOnly() async {
    newFile('/home/test/lib/a.dart', content: r'''
part of 'test.dart';
class A {}
class _A {}
''');
    newFile('/home/test/lib/test.dart', content: r'''
part 'a.dart';
class B {}
class _B {}
''');
    tracker.addContext(testAnalysisContext);

    await _doAllTrackerWork();
    _assertHasLibrary('package:test/test.dart', declarations: [
      _ExpectedDeclaration.class_('A'),
      _ExpectedDeclaration.class_('B'),
    ]);
  }

  test_readByteStore() async {
    newFile('/home/test/lib/a.dart', content: r'''
class A {}
''');
    newFile('/home/test/lib/b.dart', content: r'''
class B {}
''');
    newFile('/home/test/lib/test.dart', content: r'''
export 'a.dart' show A;
part 'b.dart';
class C {}
''');

    // The byte store is empty, fill it.
    tracker.addContext(testAnalysisContext);
    await _doAllTrackerWork();

    // Re-create tracker, will read from byte store.
    _createTracker();
    tracker.addContext(testAnalysisContext);
    await _doAllTrackerWork();

    _assertHasLibrary('package:test/test.dart', declarations: [
      _ExpectedDeclaration.class_('A'),
      _ExpectedDeclaration.class_('B'),
      _ExpectedDeclaration.class_('C'),
    ]);
  }

  test_removeContext_afterAddContext() async {
    newFile('/home/test/lib/test.dart', content: r'''
class A {}
''');

    // No libraries initially.
    expect(uriToLibrary, isEmpty);

    // Add the context, and remove it immediately.
    tracker.addContext(testAnalysisContext);
    tracker.removeContext(testAnalysisContext);

    // There is no context.
    expect(tracker.getContext(testAnalysisContext), isNull);

    // There is no work to do.
    expect(tracker.hasWork, isFalse);
    await _doAllTrackerWork();

    // So, there are no new libraries.
    expect(uriToLibrary, isEmpty);
  }

  void _assertHasDeclaration(Library library, _ExpectedDeclaration expected) {
    expect(
      library.declarations,
      contains(predicate((Declaration d) {
        return d.name == expected.name && d.kind == expected.kind;
      })),
      reason: '$expected',
    );
  }

  /// Assert that the current state has the library with the given [uri].
  ///
  /// If [declarations] provided, also checks that the library has exactly
  /// these declarations.
  void _assertHasLibrary(String uri,
      {List<_ExpectedDeclaration> declarations}) {
    var library = uriToLibrary[uri];
    expect(library, isNotNull);
    if (declarations != null) {
      expect(library.declarations, hasLength(declarations.length));
      for (var expected in declarations) {
        _assertHasDeclaration(library, expected);
      }
    }
  }

  void _assertHasNoLibrary(String uri) {
    expect(uriToLibrary, isNot(contains(uri)));
  }

  void _createTracker() {
    uriToLibrary.clear();

    tracker = DeclarationsTracker(byteStore, resourceProvider);
    tracker.changes.listen((change) {
      changes.add(change);
      for (var library in change.changed) {
        var uriStr = library.uri.toString();
        idToLibrary[library.id] = library;
        uriToLibrary[uriStr] = library;
      }
      idToLibrary.removeWhere((uriStr, library) {
        return change.removed.contains(library.id);
      });
      uriToLibrary.removeWhere((uriStr, library) {
        return change.removed.contains(library.id);
      });
    });
  }

  Future<void> _doAllTrackerWork() async {
    while (tracker.hasWork) {
      tracker.doWork();
    }
    await pumpEventQueue();
  }

  static Future pumpEventQueue([int times = 5000]) {
    if (times == 0) return new Future.value();
    return new Future.delayed(Duration.zero, () => pumpEventQueue(times - 1));
  }

  static void _assertHasLibraries(List<Library> libraries,
      {@required List<String> uriList, bool only = false}) {
    var actualUriList = libraries.map((lib) => lib.uri.toString()).toList();
    if (only) {
      expect(actualUriList, unorderedEquals(uriList));
    } else {
      expect(actualUriList, containsAll(uriList));
    }
  }
}

//class _ExpectedLibrary {
//  final Uri uri;
//  final String path;
//}

class _ExpectedDeclaration {
  final String name;
  final DeclarationKind kind;

  _ExpectedDeclaration(this.name, this.kind);

  _ExpectedDeclaration.class_(String name) : this(name, DeclarationKind.CLASS);

  _ExpectedDeclaration.classTypeAlias(String name)
      : this(name, DeclarationKind.CLASS_TYPE_ALIAS);

  _ExpectedDeclaration.enum_(String name) : this(name, DeclarationKind.ENUM);

  _ExpectedDeclaration.function(String name)
      : this(name, DeclarationKind.FUNCTION);

  _ExpectedDeclaration.functionTypeAlias(String name)
      : this(name, DeclarationKind.FUNCTION_TYPE_ALIAS);

  _ExpectedDeclaration.mixin(String name) : this(name, DeclarationKind.MIXIN);

  _ExpectedDeclaration.variable(String name)
      : this(name, DeclarationKind.VARIABLE);

  @override
  String toString() {
    return '($name, $kind)';
  }
}
