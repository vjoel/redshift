require 'rake'

PRJ = "redshift"

def cur_ruby
  require 'rbconfig'
  @cur_ruby ||= RbConfig::CONFIG["RUBY_INSTALL_NAME"]
end

def version
  @version ||= begin
    require 'redshift/redshift'
    warn "RedShift::VERSION not a string" unless
      RedShift::VERSION.kind_of? String
    RedShift::VERSION
  end
end

def tag
  @tag ||= "#{PRJ}-#{version}"
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

desc "Commit, tag, and push repo; build and push gem"
task :release => "release:is_new_version" do
  require 'tempfile'
  
  sh "gem build #{PRJ}.gemspec"

  file = Tempfile.new "template"
  begin
    file.puts "release #{version}"
    file.close
    sh "git commit --allow-empty -a -v -t #{file.path}"
  ensure
    file.close unless file.closed?
    file.unlink
  end

  sh "git tag #{tag}"
  sh "git push"
  sh "git push --tags"
  
  sh "gem push #{tag}.gem"
end

namespace :release do
  desc "Diff to latest release"
  task :diff do
    latest = `git describe --abbrev=0 --tags --match '#{PRJ}-*'`.chomp
    sh "git diff #{latest}"
  end

  desc "Log to latest release"
  task :log do
    latest = `git describe --abbrev=0 --tags --match '#{PRJ}-*'`.chomp
    sh "git log #{latest}.."
  end

  task :is_new_version do
    abort "#{tag} exists; update version!" unless `git tag -l #{tag}`.empty?
  end
end
