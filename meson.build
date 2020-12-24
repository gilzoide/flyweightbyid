project('flyweightbyid', 'd')

sources = files(
  'source/flyweightbyid.d',
)
incdir = include_directories('source')

flyweightbyid = library('flyweightbyid',
  sources,
  include_directories: incdir,
)

flyweightbyid_dep = declare_dependency(include_directories: incdir, link_with: flyweightbyid)
