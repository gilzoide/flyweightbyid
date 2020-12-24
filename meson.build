project('flyweightbyid', 'd')

sources = files(
  'source/flyweightbyid.d',
)
incdir = include_directories('source')

d_module_versions = []
if get_option('global_storage')
  d_module_versions += 'GlobalStorage'
endif

flyweightbyid = library('flyweightbyid',
  sources,
  include_directories: incdir,
  d_module_versions: d_module_versions,
)

flyweightbyid_dep = declare_dependency(include_directories: incdir, link_with: flyweightbyid)
