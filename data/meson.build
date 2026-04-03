desktop_file = i18n.merge_file(
        input: 'io.github.sitraorg.sitra.desktop.in',
       output: 'io.github.sitraorg.sitra.desktop',
         type: 'desktop',
       po_dir: '../po',
      install: true,
  install_dir: get_option('datadir') / 'applications'
)

desktop_utils = find_program('desktop-file-validate', required: false)
if desktop_utils.found()
  test('Validate desktop file', desktop_utils, args: [desktop_file])
endif

appstream_file = i18n.merge_file(
        input: 'io.github.sitraorg.sitra.metainfo.xml.in',
       output: 'io.github.sitraorg.sitra.metainfo.xml',
       po_dir: '../po',
      install: true,
  install_dir: get_option('datadir') / 'metainfo'
)

appstreamcli = find_program('appstreamcli', required: false, disabler: true)
test('Validate appstream file', appstreamcli,
     args: ['validate', '--no-net', '--explain', appstream_file])

install_data('io.github.sitraorg.sitra.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)

compile_schemas = find_program('glib-compile-schemas', required: false, disabler: true)
test('Validate schema file',
     compile_schemas,
     args: ['--strict', '--dry-run', meson.current_source_dir()])

service_conf = configuration_data()
service_conf.set('bindir', get_option('prefix') / get_option('bindir'))
configure_file(
  input: 'io.github.sitraorg.sitra.service.in',
  output: 'io.github.sitraorg.sitra.service',
  configuration: service_conf,
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)

font_files = files(
	'fonts/iosevka.ttf',
	'fonts/kalam.ttf',
	'fonts/museomoderno.ttf',
	'fonts/noto-serif.ttf'
)

install_data(
  font_files,
  install_dir: join_paths(
    get_option('prefix'),
    'share',
    'fonts',
    'io.github.sitraorg.sitra'
  )
)

subdir('icons')