unset CDPATH
# This unwieldy bit of scripting is to try to catch instances where Logstash
# was launched from a symlink, rather than a full path to the Logstash binary
if [ -L $0 ]; then
  # Launched from a symlink
  # --Test for the readlink binary
  RL=$(which readlink)
  if [ $? -eq 0 ]; then
    # readlink exists
    SOURCEPATH=$($RL $0)
  else
    # readlink not found, attempt to parse the output of stat
    SOURCEPATH=$(stat -c %N $0 | awk '{print $3}' | sed -e 's/\‘//' -e 's/\’//')
    if [ $? -ne 0 ]; then
      # Failed to execute or parse stat
      echo "Failed to set LOGSTASH_HOME from $(cd `dirname $0`/..; pwd)/bin/logstash.lib.sh"
      echo "You may need to launch Logstash with a full path instead of a symlink."
      exit 1
    fi
  fi
else
  # Not a symlink
  SOURCEPATH=$0
fi

LOGSTASH_HOME=$(cd `dirname $SOURCEPATH`/..; pwd)
export LOGSTASH_HOME

# Defaults you can override with environment variables
#LS_HEAP_SIZE="${LS_HEAP_SIZE:=1g}"

# setting ES_MIN_MEM
case ${MEMORY_SIZE:-small} in
    "micro")
       export LS_JAVA_OPTS="-Xms128m -Xmx128m"
       echo "Optimizing java process for 128M Memory...." >&2
       ;;
    "small")
       export LS_JAVA_OPTS="-Xms256m -Xmx256m"
       echo "Optimizing java process for 256M Memory...." >&2
       ;;
    "medium")
       export LS_JAVA_OPTS="-Xms512m -Xmx512m -XX:NewSize=64m -XX:PermSize=64m"
       echo "Optimizing java process for 512M Memory...." >&2
       ;;
    "large")
       export LS_JAVA_OPTS="-Xms1024m -Xmx1024m -XX:NewSize=128m -XX:PermSize=128m"
       echo "Optimizing java process for 1G Memory...." >&2
       ;;
    "2xlarge")
       export LS_JAVA_OPTS="-Xms2048m -Xmx2048m -XX:NewSize=256m -XX:PermSize=128m"
       echo "Optimizing java process for 2G Memory...." >&2
       ;;
    "4xlarge")
       export LS_JAVA_OPTS="-Xms4096m -Xmx4096m -XX:NewSize=512m -XX:PermSize=256m"
       echo "Optimizing java process for 4G Memory...." >&2
       ;;
    "8xlarge")
       export LS_JAVA_OPTS="-Xms8192m -Xmx8192m -XX:NewSize=1024m -XX:PermSize=512m"
       echo "Optimizing java process for 8G Memory...." >&2
       ;;
    16xlarge|32xlarge|64xlarge)
       export LS_JAVA_OPTS="-Xms10240m -Xmx10240m -XX:NewSize=2048m -XX:PermSize=1024m"
       echo "Optimizing java process for biger Memory...." >&2
       ;;
    *)
       export LS_JAVA_OPTS="-Xms256m -Xmx256m"
       echo "Optimizing java process for 256M Memory...." >&2
       ;;
esac

setup_java() {
  if [ -z "$JAVACMD" ] ; then
    if [ -n "$JAVA_HOME" ] ; then
      JAVACMD="$JAVA_HOME/bin/java"
    else
      JAVACMD="java"
    fi
  fi

  # Resolve full path to the java command.
  if [ ! -f "$JAVACMD" ] ; then
    JAVACMD=$(which $JAVACMD 2>/dev/null)
  fi

  if [ ! -x "$JAVACMD" ] ; then
    echo "Could not find any executable java binary. Please install java in your PATH or set JAVA_HOME." 1>&2
    exit 1
  fi

  if [ "$JAVA_OPTS" ] ; then
    echo "WARNING: Default JAVA_OPTS will be overridden by the JAVA_OPTS defined in the environment. Environment JAVA_OPTS are $JAVA_OPTS"  1>&2
  else
    # There are no JAVA_OPTS set from the client, we set a predefined
    # set of options that think are good in general
    JAVA_OPTS="$LS_JAVA_OPTS  -XX:+UseParNewGC"
    JAVA_OPTS="$JAVA_OPTS -XX:+UseConcMarkSweepGC"
    JAVA_OPTS="$JAVA_OPTS -Djava.awt.headless=true"

    JAVA_OPTS="$JAVA_OPTS -XX:CMSInitiatingOccupancyFraction=75"
    JAVA_OPTS="$JAVA_OPTS -XX:+UseCMSInitiatingOccupancyOnly"
    # Causes the JVM to dump its heap on OutOfMemory.
    JAVA_OPTS="$JAVA_OPTS -XX:+HeapDumpOnOutOfMemoryError"
    # The path to the heap dump location
    # This variable needs to be isolated since it may contain spaces
    HEAP_DUMP_PATH="-XX:HeapDumpPath=${LOGSTASH_HOME}/heapdump.hprof"
  fi

#  if [ "$LS_JAVA_OPTS" ] ; then
    # The client set the variable LS_JAVA_OPTS, choosing his own
    # set of java opts.
#    JAVA_OPTS="$JAVA_OPTS $LS_JAVA_OPTS"
#  fi

#  if [ "$LS_HEAP_SIZE" ] ; then
#    JAVA_OPTS="$JAVA_OPTS -Xmx${LS_HEAP_SIZE}"
#  fi

  if [ "$LS_USE_GC_LOGGING" ] ; then
    JAVA_OPTS="$JAVA_OPTS -XX:+PrintGCDetails"
    JAVA_OPTS="$JAVA_OPTS -XX:+PrintGCTimeStamps"
    JAVA_OPTS="$JAVA_OPTS -XX:+PrintClassHistogram"
    JAVA_OPTS="$JAVA_OPTS -XX:+PrintTenuringDistribution"
    JAVA_OPTS="$JAVA_OPTS -XX:+PrintGCApplicationStoppedTime"
    JAVA_OPTS="$JAVA_OPTS -Xloggc:./logstash-gc.log"
    echo "Writing garbage collection logs to ./logstash-gc.log"
  fi

  export JAVACMD
  export JAVA_OPTS
}

setup_drip() {
  if [ -z "$DRIP_JAVACMD" ] ; then
    JAVACMD="drip"
  fi

  # resolve full path to the drip command.
  if [ ! -f "$JAVACMD" ] ; then
    JAVACMD=$(which $JAVACMD 2>/dev/null)
  fi

  if [ ! -x "$JAVACMD" ] ; then
    echo "Could not find executable drip binary. Please install drip in your PATH"
    exit 1
  fi

  # faster JRuby startup options https://github.com/jruby/jruby/wiki/Improving-startup-time
  # since we are using drip to speed up, we may as well throw these in also
  if [ "$USE_RUBY" = "1" ] ; then
    export JRUBY_OPTS="$JRUBY_OPTS -J-XX:+TieredCompilation -J-XX:TieredStopAtLevel=1 -J-noverify"
  else
    JAVA_OPTS="$JAVA_OPTS -XX:+TieredCompilation -XX:TieredStopAtLevel=1 -noverify"
  fi
  export JAVACMD
  export DRIP_INIT_CLASS="org.jruby.main.DripMain"
  export DRIP_INIT=""
}

setup_vendored_jruby() {
  JRUBY_BIN="${LOGSTASH_HOME}/vendor/jruby/bin/jruby"

  if [ ! -f "${JRUBY_BIN}" ] ; then
    echo "Unable to find JRuby."
    echo "If you are a user, this is a bug."
    echo "If you are a developer, please run 'rake bootstrap'. Running 'rake' requires the 'ruby' program be available."
    exit 1
  fi
  VENDORED_JRUBY=1
}

setup_ruby() {
  RUBYCMD="ruby"
  VENDORED_JRUBY=
}

jruby_opts() {
  printf "%s" "--1.9"
  for i in $JAVA_OPTS ; do
    printf "%s" " -J$i"
  done
}

setup() {
  # first check if we want to use drip, which can be used in vendored jruby mode
  # and also when setting USE_RUBY=1 if the ruby interpretor is in fact jruby
  if [ "$JAVACMD" ] ; then
    if [ "$(basename $JAVACMD)" = "drip" ] ; then
      DRIP_JAVACMD=1
      USE_DRIP=1
    fi
  fi
  if [ "$USE_DRIP" = "1" ] ; then
    setup_drip
  fi

  if [ "$USE_RUBY" = "1" ] ; then
    setup_ruby
  else
    setup_java
    setup_vendored_jruby
  fi
}

ruby_exec() {
  if [ -z "$VENDORED_JRUBY" ] ; then

    # $VENDORED_JRUBY is empty so use the local "ruby" command

    if [ "$DEBUG" ] ; then
      echo "DEBUG: exec ${RUBYCMD} $@"
    fi
    exec "${RUBYCMD}" "$@"
  else

    # $VENDORED_JRUBY is non-empty so use the vendored JRuby

    if [ "$DEBUG" ] ; then
      echo "DEBUG: exec ${JRUBY_BIN} $(jruby_opts) "-J$HEAP_DUMP_PATH" $@"
    fi
    exec "${JRUBY_BIN}" $(jruby_opts) "-J$HEAP_DUMP_PATH" "$@"
  fi
}
