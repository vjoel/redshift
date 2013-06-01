require 'rake'
require 'rake/testtask'

def cur_ruby
  require 'rbconfig'
  @cur_ruby ||= RbConfig::CONFIG["RUBY_INSTALL_NAME"]
end

desc "Run unit tests"
Rake::TestTask.new :test do |t|
  t.libs << "lib"
  t.libs << "ext"
  t.test_files = FileList["test/test_*.rb"]
end

desc "build extensions for current ruby: #{RUBY_VERSION}"
task :build_ext do
  Find.find('ext/redshift') do |f|
    next unless File.basename(f) == "extconf.rb"
    d = File.dirname(f)
    Dir.chdir d do
      sh "make distclean || true"
      ruby "extconf.rb"
      sh "make"
    end
  end
end

