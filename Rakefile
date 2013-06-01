require 'rake'

def cur_ruby
  require 'rbconfig'
  @cur_ruby ||= RbConfig::CONFIG["RUBY_INSTALL_NAME"]
end

desc "Run unit tests"
task :test do |t|
  sh "cd test && RUBYLIB=../lib:../ext:$RUBYLIB ./test.rb"
end

desc "build extensions for current ruby: #{RUBY_VERSION}"
task :build_ext do
  require 'find'
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

