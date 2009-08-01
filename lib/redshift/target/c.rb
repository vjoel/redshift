# Process the selected libname or the name of the current program into
# an acceptable library name.
begin
  clib_name = ($REDSHIFT_CLIB_NAME || $0).dup
    ## should think of something better when $0=="irb"
  clib_name =
    if clib_name == "\000PWD"  # irb in ruby 1.6.5 bug
      "irb"
    elsif clib_name == "-" and ENV["RUBY_SOURCE_FILE"]
      File.basename(ENV["RUBY_SOURCE_FILE"])
        # RUBY_SOURCE_FILE can be defined by your editor/ide cmd to call ruby
    else
      File.basename(clib_name)
    end
  clib_name.sub!(/\.rb$/, '')
  clib_name.gsub!(/-/, '_')
  clib_name.sub!(/^(?=\d)/, '_')
    # other symbols will be caught in CGenerator::Library#initialize.
  clib_name << "_clib_#{RUBY_VERSION.delete('.')}"
  ## maybe name should be _ext instead of _clib?
  $REDSHIFT_CLIB_NAME = clib_name
end

$REDSHIFT_WORK_DIR ||= "tmp"

if false ### $REDSHIFT_SKIP_BUILD
  # useful for: turnkey; fast start if no changes; manual lib edits
  f = File.join($REDSHIFT_WORK_DIR, $REDSHIFT_CLIB_NAME, $REDSHIFT_CLIB_NAME)
  require f
else
  require 'redshift/target/c/library'
  require 'redshift/target/c/flow-gen'
  require 'redshift/target/c/component-gen'
  require 'redshift/target/c/world-gen'
  
  RedShift.do_library_calls
end
