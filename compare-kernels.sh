#!/bin/bash

export SCRIPT=`basename $0 | sed -e 's/\./\\\./'`
export SCRIPTDIR=`echo $0 | sed -e "s/$SCRIPT//"`
. $SCRIPTDIR/shellpacks/common.sh
. $SCRIPTDIR/shellpacks/common-config.sh
. $SCRIPTDIR/config

KERNEL_BASE=
KERNEL_COMPARE=
KERNEL_EXCLUDE=

while [ "$1" != "" ]; do
	case $1 in
	--format)
		FORMAT=$2
		FORMAT_CMD="--format $FORMAT"
		shift 2
		;;
	--output-dir)
		OUTPUT_DIRECTORY=$2
		shift 2
		;;
	--baseline)
		KERNEL_BASE=$2
		shift 2
		;;
	--compare)
		KERNEL_COMPARE="$2"
		shift 2
		;;
	--result-dir)
		cd "$2" || die Result directory does not exist or is not directory
		shift 2
		;;
	--sort-version)
		SORT_VERSION=yes
		shift
		;;
	--R)
		USE_R="--R"
		shift
		;;
	--plot-details)
		PLOT_DETAILS="yes"
		shift
		;;
	--iterations)
		ITERATIONS="$1 $2"
		FIRST_ITERATION_PREFIX="1/"
		shift 2
		;;
	*)
		echo Unrecognised argument: $1 1>&2
		shift
		;;
	esac
done


# Do Not Litter
cleanup() {
	if [ "$R_TMPDIR" != "" -a -d $R_TMPDIR ]; then
		rm -rf $R_TMPDIR
	fi
	exit
}

if [ "$USE_R" != "" ]; then
	export R_TMPDIR="`mktemp -d`"
	trap cleanup EXIT
	trap cleanup INT
	trap cleanup TERM
fi

FORMAT_CMD=
if [ "$FORMAT" != "" ]; then
	FORMAT_CMD="--format $FORMAT"
fi
if [ "$OUTPUT_DIRECTORY" != "" -a ! -e "$OUTPUT_DIRECTORY" ]; then
	mkdir -p $OUTPUT_DIRECTORY
fi
if [ "$OUTPUT_DIRECTORY" != "" -a ! -d "$OUTPUT_DIRECTORY" ]; then
	echo Output directory is not a directory
	exit -1
fi

if [ `ls "$FIRST_ITERATION_PREFIX"tests-timestamp-* 2> /dev/null | wc -l` -eq 0 ]; then
	die This does not look like a mmtests results directory
fi

# Only include kernels we have results for
if [ ! -e "$FIRST_ITERATION_PREFIX"tests-timestamp-$KERNEL_BASE ]; then
	TEMP_KERNEL_BASE=
	TEMP_KERNEL_COMPARE=
	for KERNEL in $KERNEL_COMPARE; do
		if [ -e "$FIRST_ITERATION_PREFIX"tests-timestamp-$KERNEL ]; then
			if [ "$TEMP_KERNEL_BASE" = "" ]; then
				TEMP_KERNEL_BASE=$KERNEL
			fi
			TEMP_KERNEL_COMPARE="$TEMP_KERNEL_COMPARE $KERNEL"
		fi
		KERNEL_BASE=$TEMP_KERNEL_BASE
		KERNEL_COMPARE=$TEMP_KERNEL_COMPARE
	done
fi

# Build a list of kernels
if [ "$KERNEL_BASE" != "" ]; then
	KERNEL_LIST=$KERNEL_BASE
	for KERNEL in $KERNEL_COMPARE; do
		KERNEL_LIST=$KERNEL_LIST,$KERNEL
	done
else
	[ -n "$ITERATIONS" ] && pushd $FIRST_ITERATION_PREFIX > /dev/null
	for KERNEL in `grep -H ^start tests-timestamp-* | awk -F : '{print $4" "$1}' | sort -n | awk '{print $2}' | sed -e 's/tests-timestamp-//'`; do
		EXCLUDE=no
		for TEST_KERNEL in $KERNEL_EXCLUDE; do
			if [ "$TEST_KERNEL" = "$KERNEL" ]; then
				EXCLUDE=yes
			fi
		done
		if [ "$EXCLUDE" = "no" ]; then
			if [ "$KERNEL_BASE" = "" ]; then
				KERNEL_BASE=$KERNEL
				KERNEL_LIST=$KERNEL
			else
				KERNEL_LIST="$KERNEL_LIST,$KERNEL"
			fi
		fi
	done
	[ -n "$ITERATIONS" ] && popd > /dev/null
fi

if [ "$SORT_VERSION" = "yes" ]; then
	LIST_SORT=$KERNEL_LIST
	KERNEL_LIST=
	KERNEL_BASE=
	for KERNEL in `echo $LIST_SORT | sed -e 's/,/\n/g' | sort -t . -k2 -n`; do
		if [ "$KERNEL_BASE" = "" ]; then
			KERNEL_BASE=$KERNEL
			KERNEL_LIST=$KERNEL
		else
			KERNEL_LIST="$KERNEL_LIST,$KERNEL"
		fi
	done
fi

plain() {
	IMG_SRC=$1
	echo -n "  <td><a href=\"$IMG_SRC.ps\"><img src=\"$IMG_SRC.png\"></a></td>"
}

plain_alone() {
	IMG_SRC=$1
	echo -n "  <td colspan=4><a href=\"$IMG_SRC.ps\"><img src=\"$IMG_SRC.png\"></a></td>"
}

smoothover() {
	IMG_SRC=$1
	IMG_SMOOTH=$1-smooth
	echo -n "  <td><a href=\"$IMG_SMOOTH.ps\"><img src=\"$IMG_SRC.png\" onmouseover=\"this.src='$IMG_SMOOTH.png'\" onmouseout=\"this.src='$IMG_SRC.png'\"></a></td>"
}

cat $SCRIPTDIR/shellpacks/common-header-$FORMAT 2> /dev/null
for SUBREPORT in `grep "test begin :: " "$FIRST_ITERATION_PREFIX"tests-timestamp-$KERNEL_BASE | awk '{print $4}'`; do
	COMPARE_CMD="compare-mmtests.pl -d . -b $SUBREPORT -n $KERNEL_LIST $FORMAT_CMD"
	COMPARE_BARE_CMD="compare-mmtests.pl -d . -b $SUBREPORT -n $KERNEL_LIST"
	COMPARE_R_CMD="compare-mmtests-R.sh -d . $ITERATIONS -b $SUBREPORT -n $KERNEL_LIST $FORMAT_CMD"
	GRAPH_PNG="graph-mmtests.sh -d . -b $SUBREPORT -n $KERNEL_LIST $USE_R --format png"
	GRAPH_PSC="graph-mmtests.sh -d . -b $SUBREPORT -n $KERNEL_LIST $USE_R --format \"postscript color solid\""
	echo
	case $SUBREPORT in
	dbench3)
		echo $SUBREPORT MB/sec
		eval $COMPARE_CMD --sub-heading MB/sec
		;;
	dbench4|tbench4)
		echo $SUBREPORT MB/sec
		eval $COMPARE_CMD --sub-heading MB/sec
		echo $SUBREPORT Latency
		eval $COMPARE_CMD --sub-heading Latency
		;;
	ebizzy)
		echo $SUBREPORT
		$COMPARE_CMD
		echo
		echo $SUBREPORT Per-thread
		compare-mmtests.pl -d . -b ebizzythread -n $KERNEL_LIST $FORMAT_CMD
		echo
		echo $SUBREPORT Thread spread
		compare-mmtests.pl -d . -b ebizzyrange -n $KERNEL_LIST $FORMAT_CMD
		;;
	fsmark-single|fsmark-threaded)
		echo $SUBREPORT Files/sec
		eval $COMPARE_CMD --sub-heading Files/sec
		echo $SUBREPORT Latency
		eval $COMPARE_CMD --sub-heading Overhead
		;;
	loopdd)
		echo $SUBREPORT Throughput
		eval $COMPARE_CMD
		echo
		echo $SUBREPORT DD-Time
		eval $COMPARE_CMD --sub-heading ddtime
		echo
		echo $SUBREPORT CPU-Time
		eval $COMPARE_CMD --sub-heading elapsed
		;;
	pgbench)
		echo $SUBREPORT Initialisation
		eval $COMPARE_CMD --sub-heading LoadTime
		echo
		echo $SUBREPORT Transactions
		eval $COMPARE_CMD
		echo
		echo $SUBREPORT Time
		eval $COMPARE_CMD --sub-heading TransTime
		echo
		;;
	preaddd)
		echo $SUBREPORT Throughput
		eval $COMPARE_CMD
		echo
		echo $SUBREPORT DD-Time
		eval $COMPARE_CMD --sub-heading ddtime
		echo
		;;

	specjvm)
		echo $SUBREPORT
		eval $COMPARE_CMD
		;;
	specjbb)
		echo $SUBREPORT
		$COMPARE_CMD
		echo $SUBREPORT Peaks
		compare-mmtests.pl -d . -b specjbbpeak -n $KERNEL_LIST $FORMAT_CMD
		;;
	sysbench)
		echo $SUBREPORT Initialisation
		eval $COMPARE_CMD --sub-heading LoadTime
		echo
		echo $SUBREPORT Transactions
		eval $COMPARE_CMD
		echo
		echo $SUBREPORT Time
		eval $COMPARE_CMD --sub-heading TransTime
		echo
		;;

	tiobench)
		echo $SUBREPORT MB/sec
		eval $COMPARE_CMD --sub-heading MB/sec
		echo
		echo $SUBREPORT Maximum Latency
		eval $COMPARE_CMD --sub-heading MaxLatency
		;;
	*)
		echo $SUBREPORT
		# Try R if requested, fallback to perl when datatype is unsupported
		if [ "$USE_R" != "" ]; then
			eval $COMPARE_R_CMD
		else
			false
		fi || eval $COMPARE_CMD
	esac
	echo
	eval $COMPARE_CMD --print-monitor duration
	echo
	eval $COMPARE_CMD --print-monitor mmtests-vmstat

	TEST=
	if [ `ls iostat-* 2> /dev/null | wc -l` -gt 0 ]; then
		eval $COMPARE_BARE_CMD --print-monitor iostat 2> /dev/null > /tmp/iostat-$$
		TEST=`head -4 /tmp/iostat-$$ | tail -1 | awk '{print $3}' | cut -d. -f1`
	fi
	if [ "$TEST" != "" ] && [ $TEST -gt 5 ]; then
		echo
		eval $COMPARE_CMD --print-monitor iostat
		PARAM_LIST="avgqz await r_await w_await"
		TEST=`grep Device: /tmp/iostat-$$ | grep rsec | head -1`
		if [ "$TEST" != "" ]; then
			PARAM_LIST="avgqz await"
		fi
		if [ "$FORMAT" = "html" -a -d "$OUTPUT_DIRECTORY" ]; then
			for DEVICE in sda; do
				echo "<table class=\"resultsGraphs\">"
				echo "<tr>"
				for PARAM in avgqusz await r_await w_await; do
					eval $GRAPH_PNG --title \"$DEVICE $PARAM\"   --print-monitor iostat --sub-heading $DEVICE-$PARAM --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-$DEVICE-$PARAM.png
					eval $GRAPH_PNG --title \"$DEVICE $PARAM\"   --print-monitor iostat --sub-heading $DEVICE-$PARAM --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-$DEVICE-$PARAM-smooth.png  --smooth
					eval $GRAPH_PSC --title \"$DEVICE $PARAM\"   --print-monitor iostat --sub-heading $DEVICE-$PARAM --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-$DEVICE-$PARAM.ps
					eval $GRAPH_PSC --title \"$DEVICE $PARAM\"   --print-monitor iostat --sub-heading $DEVICE-$PARAM --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-$DEVICE-$PARAM-smooth.ps  --smooth
					smoothover graph-$SUBREPORT-$DEVICE-$PARAM
				done
				echo "</tr>"
				echo "<tr>"
				for PARAM in avgrqsz rrqm wrqm; do
					eval $GRAPH_PNG --title \"$DEVICE $PARAM\"   --print-monitor iostat --sub-heading $DEVICE-$PARAM --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-$DEVICE-$PARAM.png
					eval $GRAPH_PNG --title \"$DEVICE $PARAM\"   --print-monitor iostat --sub-heading $DEVICE-$PARAM --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-$DEVICE-$PARAM-smooth.png  --smooth
					eval $GRAPH_PSC --title \"$DEVICE $PARAM\"   --print-monitor iostat --sub-heading $DEVICE-$PARAM --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-$DEVICE-$PARAM.ps
					eval $GRAPH_PSC --title \"$DEVICE $PARAM\"   --print-monitor iostat --sub-heading $DEVICE-$PARAM --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-$DEVICE-$PARAM-smooth.ps  --smooth
					smoothover graph-$SUBREPORT-$DEVICE-$PARAM
				done

				echo "</table>"
			done
		fi
	fi
	rm -f /tmp/iostat-$$

	GRANULARITY=
	if [ `ls read-latency-$KERNEL_BASE-* 2> /dev/null | wc -l` -gt 0 ]; then
		if [ `cat read-latency-$KERNEL_BASE-* | wc -l` -gt 50000 ]; then
			GRANULARITY="--sub-heading batch=100"
		fi
		if [ "$FORMAT" = "html" -a -d "$OUTPUT_DIRECTORY" ]; then
			echo "<table class=\"resultsGraphs\">"
		fi
		eval $COMPARE_CMD $GRANULARITY                --print-monitor read-latency
		echo
		eval $COMPARE_CMD --sub-heading breakdown=100 --print-monitor read-latency
		if [ "$FORMAT" = "html" -a -d "$OUTPUT_DIRECTORY" ]; then
			echo "</table>"
		fi
	fi
	if [ `ls write-latency-$KERNEL_BASE-* 2> /dev/null | wc -l` -gt 0 ]; then
		if [ `cat write-latency-$KERNEL_BASE-* | wc -l` -gt 50000 ]; then
			GRANULARITY="--sub-heading batch=100"
		fi
		if [ "$FORMAT" = "html" -a -d "$OUTPUT_DIRECTORY" ]; then
			echo "<table class=\"resultsGraphs\">"
		fi
		eval $COMPARE_CMD $GRANULARITY                --print-monitor write-latency
		echo
		eval $COMPARE_CMD --sub-heading breakdown=100 --print-monitor write-latency
		if [ "$FORMAT" = "html" -a -d "$OUTPUT_DIRECTORY" ]; then
			echo "</table>"
		fi
	fi

	# Graphs
	if [ "$FORMAT" = "html" -a -d "$OUTPUT_DIRECTORY" ]; then
		echo "<table class=\"resultsGraphs\">"

		case $SUBREPORT in
		aim9)
			;;
		bonnie)
			echo "<tr>"
			COUNT=0
			for HEADING in "SeqOut Char" "SeqOut Block" "SeqOut Rewrite" "SeqIn Char" "SeqIn Block" "Random seeks"; do
				if [ $((COUNT%3)) -eq 0 ]; then
					echo "<tr>"
				fi
				SUBHEADING=`echo $HEADING | sed -e 's/ //g'`

				eval $GRAPH_PNG --title \"$SUBREPORT $HEADING\" --sub-heading $SUBHEADING --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-$SUBHEADING.png
				eval $GRAPH_PSC --title \"$SUBREPORT $HEADING\" --sub-heading $SUBHEADING --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-$SUBHEADING.ps
				plain graph-$SUBREPORT-$SUBHEADING
				COUNT=$((COUNT+1))
				if [ $((COUNT%3)) -eq 0 ]; then
					echo "</tr>"
				fi
			done
			;;
		dbench3)
			echo "<tr>"
			eval $GRAPH_PNG --logX --title \"$SUBREPORT $HEADING\" --sub-heading MB/sec --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-MB_sec.png
			eval $GRAPH_PSC --logX --title \"$SUBREPORT $HEADING\" --sub-heading MB/sec --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-MB_sec.ps
			plain graph-$SUBREPORT-MB_sec
			echo "</tr>"
			;;
		dbench4|tbench4)
			echo "<tr>"
			for HEADING in MB/sec Latency; do
				PRINTHEADING=$HEADING
				if [ "$HEADING" = "MB/sec" ]; then
					PRINTHEADING=MB_sec
				fi
				eval $GRAPH_PNG --logX --title \"$SUBREPORT $HEADING\" --sub-heading $HEADING --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-$PRINTHEADING.png --y-label $HEADING
				eval $GRAPH_PSC --logX --title \"$SUBREPORT $HEADING\" --sub-heading $HEADING --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-$PRINTHEADING.ps  --y-label $HEADING
				plain graph-$SUBREPORT-$PRINTHEADING
			done
			echo "</tr>"
			;;
		ffsb)
			;;
		fsmark-single|fsmark-threaded)
			echo "<tr>"
			for HEADING in Files/sec Overhead; do
				PRINTHEADING=$HEADING
				if [ "$HEADING" = "Files/sec" ]; then
					PRINTHEADING=Files_sec
				fi
				eval $GRAPH_PNG --title \"$SUBREPORT $HEADING\" --sub-heading $HEADING --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-$PRINTHEADING.png
				eval $GRAPH_PSC --title \"$SUBREPORT $HEADING\" --sub-heading $HEADING --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-$PRINTHEADING.ps
				plain graph-$SUBREPORT-$PRINTHEADING
			done
			echo "</tr>"
			;;
		hackbench-pipes|hackbench-sockets)
			echo "<tr>"
			eval $GRAPH_PNG --logX --title \"$SUBREPORT\" --output $OUTPUT_DIRECTORY/graph-$SUBREPORT.png --y-label latency
			eval $GRAPH_PSC --logX --title \"$SUBREPORT\" --output $OUTPUT_DIRECTORY/graph-$SUBREPORT.ps  --y-label latency
			plain graph-$SUBREPORT
			echo "</tr>"
			;;
		highalloc)
			;;
		gitcheckout)
			;;
		kernbench|starve)
			echo "<tr>"
			for HEADING in User System Elapsed CPU; do
				eval $GRAPH_PNG --title \"$SUBREPORT $HEADING\" --sub-heading $HEADING --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-$HEADING.png
				eval $GRAPH_PSC --title \"$SUBREPORT $HEADING\" --sub-heading $HEADING --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-$HEADING.ps
				plain graph-$SUBREPORT-$HEADING
			done
			echo "</tr>"
			;;
		largedd)
			;;
		micro)
			;;
		nas-mpi)
			;;
		nas-ser)
			;;
		pagealloc)
			;;
		pft)
			;;
		postmark)
			;;
		specjvm)
			;;
		stress-highalloc)
			echo "<tr>"
			for HEADING in latency-1 latency-2 latency-3; do
				eval $GRAPH_PNG --logY --title \"$SUBREPORT $HEADING\" --sub-heading $HEADING --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-$HEADING.png
				eval $GRAPH_PSC --logY --title \"$SUBREPORT $HEADING\" --sub-heading $HEADING --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-$HEADING.ps
				plain graph-$SUBREPORT-$HEADING
			done
			echo "</tr>"
			;;
		tiobench)
			CLIENTS=`$COMPARE_BARE_CMD | grep ^Min | awk '{print $2}' | awk -F - '{print $3}' | sort -n | uniq`
			for HEADING in MB/sec AvgLatency MaxLatency; do
				PRINT_HEADING=`echo $HEADING | sed -e 's/\///'`
				for OPERATION in SeqRead RandRead SeqWrite RandWrite; do
					echo "<tr>"
					for CLIENT in $CLIENTS; do
						eval $GRAPH_PNG --title \"$OPERATION-$CLIENT\" --y-label $HEADING --sub-heading $OPERATION-$HEADING-$CLIENT --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-$OPERATION-$PRINT_HEADING-$CLIENT.png
						eval $GRAPH_PSC --title \"$OPERATION-$CLIENT\" --y-label $HEADING --sub-heading $OPERATION-$HEADING-$CLIENT --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-$OPERATION-$PRINT_HEADING-$CLIENT.ps
						plain graph-$SUBREPORT-$OPERATION-$PRINT_HEADING-$CLIENT
					done
					echo "</tr>"
				done
			done
			;;
		vmr-stream)
			;;
		*)
			eval $GRAPH_PNG --title \"$SUBREPORT\" --output $OUTPUT_DIRECTORY/graph-$SUBREPORT.png
			eval $GRAPH_PSC --title \"$SUBREPORT\" --output $OUTPUT_DIRECTORY/graph-$SUBREPORT.ps
			if [ "$USE_R" != "" ]; then
				eval $GRAPH_PNG --title \"$SUBREPORT\" --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-smooth.png --smooth
				eval $GRAPH_PSC --title \"$SUBREPORT\" --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-smooth.ps --smooth
			fi
			if [ -e $OUTPUT_DIRECTORY/graph-$SUBREPORT.png ]; then
				if [ -e $OUTPUT_DIRECTORY/graph-$SUBREPORT-smooth.png ]; then
					smoothover graph-$SUBREPORT
				else
					plain graph-$SUBREPORT
				fi
			else
				echo "<tr><td>No graph representation</td></tr>"
			fi
			if [ "$PLOT_DETAILS" != "" ]; then
				eval $GRAPH_PNG --title \"$SUBREPORT\" --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-singletest --plottype run-sequence --separate-tests
				eval $GRAPH_PNG --title \"$SUBREPORT\" --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-singletest --plottype run-sequence --separate-tests --smooth
				for TEST_PLOT in $OUTPUT_DIRECTORY/graph-$SUBREPORT-singletest-*.png; do
					[[ $TEST_PLOT =~ "-smooth.png" ]] && continue
					dest=`basename $TEST_PLOT .png`
					smoothover $dest
				done
			fi
		esac
		echo "</table>"

		# Monitor graphs for this test
		echo "<table class=\"monitorGraphs\">"
		if [ `ls read-latency-$KERNEL_BASE-* 2> /dev/null | wc -l` -gt 0 ]; then
			eval $GRAPH_PNG $GRANULARITY --title \"Read Latency\" --print-monitor read-latency --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-read-latency.png
			eval $GRAPH_PNG $GRANULARITY --title \"Read Latency\" --print-monitor read-latency --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-read-latency-smooth.png --smooth
			eval $GRAPH_PSC $GRANULARITY --title \"Read Latency\" --print-monitor read-latency --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-read-latency.ps
			eval $GRAPH_PSC $GRANULARITY --title \"Read Latency\" --print-monitor read-latency --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-read-latency-smooth.ps --smooth
			smoothover graph-$SUBREPORT-read-latency
		fi
		if [ `ls write-latency-$KERNEL_BASE-* 2> /dev/null | wc -l` -gt 0 ]; then
			eval $GRAPH_PNG $GRANULARITY --title \"Write Latency\" --print-monitor write-latency --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-write-latency.png
			eval $GRAPH_PNG $GRANULARITY --title \"Write Latency\" --print-monitor write-latency --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-write-latency-smooth.png --smooth
			eval $GRAPH_PSC $GRANULARITY --title \"Write Latency\" --print-monitor write-latency --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-write-latency.ps
			eval $GRAPH_PSC $GRANULARITY --title \"Write Latency\" --print-monitor write-latency --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-write-latency-smooth.ps --smooth
			smoothover graph-$SUBREPORT-write-latency
		fi
		if [ `ls inbox-open-$KERNEL_BASE-* 2> /dev/null | wc -l` -gt 0 ]; then
			eval $GRAPH_PNG $GRANULARITY --title \"Mail Read Latency\" --print-monitor inbox-open --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-inbox-open.png
			eval $GRAPH_PNG $GRANULARITY --title \"Mail Read Latency\" --print-monitor inbox-open --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-inbox-open-smooth.png --smooth
			eval $GRAPH_PSC $GRANULARITY --title \"Mail Read Latency\" --print-monitor inbox-open --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-inbox-open.ps
			eval $GRAPH_PSC $GRANULARITY --title \"Mail Read Latency\" --print-monitor inbox-open --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-inbox-open-smooth.ps --smooth
			smoothover graph-$SUBREPORT-inbox-open
		fi
		if [ `ls vmstat-$KERNEL_BASE-* | wc -l` -gt 0 ]; then
			eval $GRAPH_PNG --title \"User CPU Usage\"   --print-monitor vmstat --sub-heading us --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-us.png
			eval $GRAPH_PSC --title \"User CPU Usage\"   --print-monitor vmstat --sub-heading us --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-us.ps
			eval $GRAPH_PNG --title \"System CPU Usage\" --print-monitor vmstat --sub-heading sy --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-sy.png
			eval $GRAPH_PSC --title \"System CPU Usage\" --print-monitor vmstat --sub-heading sy --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-sy.ps
			eval $GRAPH_PNG --title \"Wait CPU Usage\"   --print-monitor vmstat --sub-heading wa --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-wa.png
			eval $GRAPH_PSC --title \"Wait CPU Usage\"   --print-monitor vmstat --sub-heading wa --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-ay.ps
			eval $GRAPH_PNG --title \"User CPU Usage\"   --print-monitor vmstat --sub-heading us --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-us-smooth.png --smooth
			eval $GRAPH_PSC --title \"User CPU Usage\"   --print-monitor vmstat --sub-heading us --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-us-smooth.ps  --smooth
			eval $GRAPH_PNG --title \"System CPU Usage\" --print-monitor vmstat --sub-heading sy --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-sy-smooth.png --smooth
			eval $GRAPH_PSC --title \"System CPU Usage\" --print-monitor vmstat --sub-heading sy --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-sy-smooth.ps  --smooth
			eval $GRAPH_PNG --title \"Wait CPU Usage\"   --print-monitor vmstat --sub-heading wa --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-wa-smooth.png --smooth
			eval $GRAPH_PSC --title \"Wait CPU Usage\"   --print-monitor vmstat --sub-heading wa --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-ay-smooth.ps  --smooth


			echo "<tr>"
			smoothover graph-$SUBREPORT-vmstat-us
			smoothover graph-$SUBREPORT-vmstat-sy
			smoothover graph-$SUBREPORT-vmstat-wa
			echo "</tr>"
		fi

		if [ `ls vmstat-$KERNEL_BASE-* | wc -l` -gt 0 ]; then
			eval $GRAPH_PNG --title \"Free Memory\"      --print-monitor vmstat --sub-heading free --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-free.png
			eval $GRAPH_PSC --title \"Free Memory\"      --print-monitor vmstat --sub-heading free --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-free.ps
			eval $GRAPH_PNG --title \"Context Switches\" --print-monitor vmstat --sub-heading cs --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-cs.png
			eval $GRAPH_PSC --title \"Context Switches\" --print-monitor vmstat --sub-heading cs --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-cs.ps
			eval $GRAPH_PNG --title \"Interrupts\"       --print-monitor vmstat --sub-heading in --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-in.png
			eval $GRAPH_PSC --title \"Interrupts\"       --print-monitor vmstat --sub-heading in --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-in.ps
			eval $GRAPH_PNG --title \"Context Switches\" --print-monitor vmstat --sub-heading cs --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-cs-smooth.png --smooth
			eval $GRAPH_PSC --title \"Context Switches\" --print-monitor vmstat --sub-heading cs --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-cs-smooth.ps  --smooth
			eval $GRAPH_PNG --title \"Interrupts\"       --print-monitor vmstat --sub-heading in --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-in-smooth.png --smooth
			eval $GRAPH_PSC --title \"Interrupts\"       --print-monitor vmstat --sub-heading in --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-in-smooth.ps  --smooth

			echo "<tr>"
			plain graph-$SUBREPORT-vmstat-free
			smoothover graph-$SUBREPORT-vmstat-cs
			smoothover graph-$SUBREPORT-vmstat-in
			echo "</tr>"
		fi
		if [ `ls proc-vmstat-$KERNEL_BASE-* | wc -l` -gt 0 ]; then
			eval $GRAPH_PNG --title \"THPages\"    --print-monitor proc-vmstat --sub-heading nr_anon_transparent_hugepages --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-thp.png
			eval $GRAPH_PSC --title \"THPages\"    --print-monitor proc-vmstat --sub-heading nr_anon_transparent_hugepages --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-thp.ps
			eval $GRAPH_PNG --title \"Anon Pages\" --print-monitor proc-vmstat --sub-heading mmtests_total_anon --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-anon.png
			eval $GRAPH_PSC --title \"Anon Pages\" --print-monitor proc-vmstat --sub-heading mmtests_total_anon --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-anon.ps
			eval $GRAPH_PNG --title \"File Pages\" --print-monitor proc-vmstat --sub-heading nr_file_pages --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-file.png
			eval $GRAPH_PSC --title \"File Pages\" --print-monitor proc-vmstat --sub-heading nr_file_pages --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-file.ps
			eval $GRAPH_PNG --title \"THPages\"    --print-monitor proc-vmstat --sub-heading nr_anon_transparent_hugepages --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-thp-smooth.png --smooth
			eval $GRAPH_PSC --title \"THPages\"    --print-monitor proc-vmstat --sub-heading nr_anon_transparent_hugepages --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-thp-smooth.ps  --smooth
			eval $GRAPH_PNG --title \"Anon Pages\" --print-monitor proc-vmstat --sub-heading mmtests_total_anon --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-anon-smooth.png                --smooth
			eval $GRAPH_PSC --title \"Anon Pages\" --print-monitor proc-vmstat --sub-heading mmtests_total_anon --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-anon-smooth.ps                 --smooth
			eval $GRAPH_PNG --title \"File Pages\" --print-monitor proc-vmstat --sub-heading nr_file_pages --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-file-smooth.png                --smooth
			eval $GRAPH_PSC --title \"File Pages\" --print-monitor proc-vmstat --sub-heading nr_file_pages --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-file-smooth.ps                 --smooth

			echo "<tr>"
			smoothover graph-$SUBREPORT-proc-vmstat-thp
			smoothover graph-$SUBREPORT-proc-vmstat-anon
			smoothover graph-$SUBREPORT-proc-vmstat-file
			echo "</tr>"

                        eval $GRAPH_PNG --title \"Total Sector IO\" --print-monitor proc-vmstat --sub-heading pgpgtotal  --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-pgptotal.png
                        eval $GRAPH_PSC --title \"Total Sector IO\" --print-monitor proc-vmstat --sub-heading pgpgtotal  --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-pgptotal.ps
			eval $GRAPH_PNG --title \"Sector Reads\"      --print-monitor proc-vmstat --sub-heading pgpgin     --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-pgpin.png
			eval $GRAPH_PSC --title \"Sector Reads\"      --print-monitor proc-vmstat --sub-heading pgpgin     --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-pgpin.ps
			eval $GRAPH_PNG --title \"Sector Writes\"     --print-monitor proc-vmstat --sub-heading pgpgout    --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-pgpout.png
			eval $GRAPH_PSC --title \"Sector Writes\"     --print-monitor proc-vmstat --sub-heading pgpgout    --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-pgpout.ps
			eval $GRAPH_PNG --title \"Total Sector IO\" --print-monitor proc-vmstat --sub-heading pgpgtotal  --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-pgptotal-smooth.png  --smooth
			eval $GRAPH_PSC --title \"Total Sector IO\" --print-monitor proc-vmstat --sub-heading pgpgtotal  --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-pgptotal-smooth.ps   --smooth
			eval $GRAPH_PNG --title \"Sector Reads\"      --print-monitor proc-vmstat --sub-heading pgpgin     --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-pgpin-smooth.png  --smooth
			eval $GRAPH_PSC --title \"Sector Reads\"      --print-monitor proc-vmstat --sub-heading pgpgin     --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-pgpin-smooth.ps   --smooth
			eval $GRAPH_PNG --title \"Sector Writes\"     --print-monitor proc-vmstat --sub-heading pgpgout    --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-pgpout-smooth.png --smooth
			eval $GRAPH_PSC --title \"Sector Writes\"     --print-monitor proc-vmstat --sub-heading pgpgout    --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-pgpout-smooth.ps  --smooth

			echo "<tr>"
			smoothover graph-$SUBREPORT-proc-vmstat-pgptotal
			smoothover graph-$SUBREPORT-proc-vmstat-pgpin
			smoothover graph-$SUBREPORT-proc-vmstat-pgpout
			echo "</tr>"
		fi
		if [ `ls proc-vmstat-$KERNEL_BASE-* | wc -l` -gt 0 ] && [ `awk '{print $12}' vmstat-* | max` -gt 0 ]; then
			eval $GRAPH_PNG --title \"Swap Usage\" --print-monitor vmstat --sub-heading swpd --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-swpd.png
			eval $GRAPH_PSC --title \"Swap Usage\" --print-monitor vmstat --sub-heading swpd --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-swpd.ps
			eval $GRAPH_PNG --title \"Swap Ins\"   --print-monitor vmstat --sub-heading si   --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-si.png
			eval $GRAPH_PSC --title \"Swap Ins\"   --print-monitor vmstat --sub-heading si   --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-si.ps
			eval $GRAPH_PNG --title \"Swap Ins\"   --print-monitor vmstat --sub-heading si   --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-si-smooth.png --smooth
			eval $GRAPH_PSC --title \"Swap Ins\"   --print-monitor vmstat --sub-heading si   --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-si-smooth.ps --smooth
			eval $GRAPH_PNG --title \"Swap Outs\"  --print-monitor vmstat --sub-heading so   --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-so.png
			eval $GRAPH_PSC --title \"Swap Outs\"  --print-monitor vmstat --sub-heading so   --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-so.ps
			eval $GRAPH_PNG --title \"Swap Outs\"  --print-monitor vmstat --sub-heading so   --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-so-smooth.png --smooth
			eval $GRAPH_PSC --title \"Swap Outs\"  --print-monitor vmstat --sub-heading so   --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-vmstat-so-smooth.ps --smooth

			echo "<tr>"
			plain graph-$SUBREPORT-vmstat-swpd
			smoothover graph-$SUBREPORT-vmstat-si
			smoothover graph-$SUBREPORT-vmstat-so
			echo "</tr>"
		fi

		if [ `ls top-* 2> /dev/null | wc -l` -gt 0 ] && [ `zgrep kswapd top-* | awk '{print $10}' | max | cut -d. -f1` -gt 0 ]; then
			eval $GRAPH_PNG --title \"Direct Reclaim Scan\"  --print-monitor proc-vmstat --sub-heading mmtests_direct_scan  --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-direct-scan.png
			eval $GRAPH_PSC --title \"Direct Reclaim Scan\"  --print-monitor proc-vmstat --sub-heading mmtests_direct_scan  --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-direct-scan.ps
			eval $GRAPH_PNG --title \"Direct Reclaim Scan\"  --print-monitor proc-vmstat --sub-heading mmtests_direct_scan  --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-direct-scan-smooth.png --smooth
			eval $GRAPH_PSC --title \"Direct Reclaim Scan\"  --print-monitor proc-vmstat --sub-heading mmtests_direct_scan  --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-direct-scan-smooth.ps --smooth
			eval $GRAPH_PNG --title \"Direct Reclaim Steal\" --print-monitor proc-vmstat --sub-heading mmtests_direct_steal --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-direct-steal.png
			eval $GRAPH_PSC --title \"Direct Reclaim Steal\" --print-monitor proc-vmstat --sub-heading mmtests_direct_steal --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-direct-steal.ps
			eval $GRAPH_PNG --title \"Direct Reclaim Steal\" --print-monitor proc-vmstat --sub-heading mmtests_direct_steal --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-direct-steal-smooth.png --smooth
			eval $GRAPH_PSC --title \"Direct Reclaim Steal\" --print-monitor proc-vmstat --sub-heading mmtests_direct_steal --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-direct-steal-smooth.ps --smooth
			eval $GRAPH_PNG --title \"Direct Reclaim Efficiency\" --print-monitor proc-vmstat --sub-heading mmtests_direct_efficiency --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-direct-efficiency.png
			eval $GRAPH_PSC --title \"Direct Reclaim Efficiency\" --print-monitor proc-vmstat --sub-heading mmtests_direct_efficiency --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-direct-efficiency.ps
			eval $GRAPH_PNG --title \"Direct Reclaim Efficiency\" --print-monitor proc-vmstat --sub-heading mmtests_direct_efficiency --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-direct-efficiency-smooth.png --smooth
			eval $GRAPH_PSC --title \"Direct Reclaim Efficiency\" --print-monitor proc-vmstat --sub-heading mmtests_direct_efficiency --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-direct-efficiency-smooth.ps --smooth
			echo "<tr>"
			smoothover graph-$SUBREPORT-proc-vmstat-direct-scan
			smoothover graph-$SUBREPORT-proc-vmstat-direct-steal
			smoothover graph-$SUBREPORT-proc-vmstat-direct-efficiency
			echo "</tr>"


			eval $GRAPH_PNG --title \"KSwapd Reclaim Scan\"  --print-monitor proc-vmstat --sub-heading mmtests_kswapd_scan  --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-kswapd-scan.png
			eval $GRAPH_PSC --title \"KSwapd Reclaim Scan\"  --print-monitor proc-vmstat --sub-heading mmtests_kswapd_scan  --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-kswapd-scan.ps
			eval $GRAPH_PNG --title \"KSwapd Reclaim Scan\"  --print-monitor proc-vmstat --sub-heading mmtests_kswapd_scan  --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-kswapd-scan-smooth.png --smooth
			eval $GRAPH_PSC --title \"KSwapd Reclaim Scan\"  --print-monitor proc-vmstat --sub-heading mmtests_kswapd_scan  --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-kswapd-scan-smooth.ps --smooth
			eval $GRAPH_PNG --title \"KSwapd Reclaim Steal\" --print-monitor proc-vmstat --sub-heading mmtests_kswapd_steal --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-kswapd-steal.png
			eval $GRAPH_PSC --title \"KSwapd Reclaim Steal\" --print-monitor proc-vmstat --sub-heading mmtests_kswapd_steal --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-kswapd-steal.ps
			eval $GRAPH_PNG --title \"KSwapd Reclaim Steal\" --print-monitor proc-vmstat --sub-heading mmtests_kswapd_steal --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-kswapd-steal-smooth.png --smooth
			eval $GRAPH_PSC --title \"KSwapd Reclaim Steal\" --print-monitor proc-vmstat --sub-heading mmtests_kswapd_steal --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-kswapd-steal-smooth.ps --smooth
			eval $GRAPH_PNG --title \"KSwapd Reclaim Efficiency\" --print-monitor proc-vmstat --sub-heading mmtests_kswapd_efficiency --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-kswapd-efficiency.png
			eval $GRAPH_PSC --title \"KSwapd Reclaim Efficiency\" --print-monitor proc-vmstat --sub-heading mmtests_kswapd_efficiency --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-kswapd-efficiency.ps
			eval $GRAPH_PNG --title \"KSwapd Reclaim Efficiency\" --print-monitor proc-vmstat --sub-heading mmtests_kswapd_efficiency --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-kswapd-efficiency-smooth.png --smooth
			eval $GRAPH_PSC --title \"KSwapd Reclaim Efficiency\" --print-monitor proc-vmstat --sub-heading mmtests_kswapd_efficiency --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-kswapd-efficiency-smooth.ps --smooth

			echo "<tr>"
			smoothover graph-$SUBREPORT-proc-vmstat-kswapd-scan
			smoothover graph-$SUBREPORT-proc-vmstat-kswapd-steal
			smoothover graph-$SUBREPORT-proc-vmstat-kswapd-efficiency
			echo "</tr>"

			eval $GRAPH_PNG --title \"KSwapd CPU Usage\"    --print-monitor top                                                 --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-top-kswapd.png
			eval $GRAPH_PSC --title \"KSwapd CPU Usage\"    --print-monitor top                                                 --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-top-kswapd.ps
			eval $GRAPH_PNG --title \"KSwapd CPU Usage\"    --print-monitor top                                                 --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-top-kswapd-smooth.png --smooth
			eval $GRAPH_PSC --title \"KSwapd CPU Usage\"    --print-monitor top                                                 --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-top-kswapd-smooth.ps --smooth
			eval $GRAPH_PNG --title \"File Reclaim Writes\" --print-monitor proc-vmstat --sub-heading mmtests_vmscan_write_file --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-reclaim-file-writes.png
			eval $GRAPH_PSC --title \"File Reclaim Writes\" --print-monitor proc-vmstat --sub-heading mmtests_vmscan_write_file --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-reclaim-file-writes.ps
			eval $GRAPH_PNG --title \"File Reclaim Writes\" --print-monitor proc-vmstat --sub-heading mmtests_vmscan_write_file --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-reclaim-file-writes-smooth.png --smooth
			eval $GRAPH_PSC --title \"File Reclaim Writes\" --print-monitor proc-vmstat --sub-heading mmtests_vmscan_write_file --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-reclaim-file-writes-smooth.ps --smooth
			eval $GRAPH_PNG --title \"Anon Reclaim Writes\" --print-monitor proc-vmstat --sub-heading mmtests_vmscan_write_anon --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-reclaim-anon-writes.png
			eval $GRAPH_PSC --title \"Anon Reclaim Writes\" --print-monitor proc-vmstat --sub-heading mmtests_vmscan_write_anon --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-reclaim-anon-writes.ps
			eval $GRAPH_PNG --title \"Anon Reclaim Writes\" --print-monitor proc-vmstat --sub-heading mmtests_vmscan_write_anon --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-reclaim-anon-writes-smooth.png --smooth
			eval $GRAPH_PSC --title \"Anon Reclaim Writes\" --print-monitor proc-vmstat --sub-heading mmtests_vmscan_write_anon --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-reclaim-anon-writes-smooth.ps --smooth

			echo "<tr>"
			smoothover graph-$SUBREPORT-top-kswapd
			smoothover graph-$SUBREPORT-proc-vmstat-reclaim-file-writes
			smoothover graph-$SUBREPORT-proc-vmstat-reclaim-anon-writes
			echo "</tr>"
		fi

		if [ `ls numa-meminfo-* 2> /dev/null | wc -l` -gt 0 ] && [ `zgrep ^Node numa-meminfo-* | awk '{print $2}' | sort | uniq | wc -l` -gt 1 ]; then
			eval $GRAPH_PNG --title \"NUMA Memory Balance\" --print-monitor Numanodeusage   --sub-heading MemoryBalance         --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-numa-memory-balance.png
			eval $GRAPH_PSC --title \"NUMA Memory Balance\" --print-monitor Numanodeusage   --sub-heading MemoryBalance         --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-numa-memory-balance.ps
			eval $GRAPH_PNG --title \"NUMA Memory Balance\" --print-monitor Numanodeusage   --sub-heading MemoryBalance         --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-numa-memory-balance-smooth.png --smooth
			eval $GRAPH_PSC --title \"NUMA Memory Balance\" --print-monitor Numanodeusage   --sub-heading MemoryBalance         --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-numa-memory-balance-smooth.ps --smooth
			eval $GRAPH_PNG --title \"Pages migrated\"      --print-monitor proc-vmstat     --sub-heading pgmigrate_success     --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-pgmigrate_success.png
			eval $GRAPH_PSC --title \"Pages migrated\"      --print-monitor proc-vmstat     --sub-heading pgmigrate_success     --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-pgmigrate_success.ps
			eval $GRAPH_PNG --title \"Pages migrated\"      --print-monitor proc-vmstat     --sub-heading pgmigrate_success     --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-pgmigrate_success-smooth.png --smooth
			eval $GRAPH_PSC --title \"Pages migrated\"      --print-monitor proc-vmstat     --sub-heading pgmigrate_success     --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-pgmigrate_success-smooth.ps --smooth
			eval $GRAPH_PNG --title \"NUMA PTE Updates\"    --print-monitor proc-vmstat     --sub-heading numa_pte_updates      --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-numa-pte-updates.png
			eval $GRAPH_PSC --title \"NUMA PTE Updates\"    --print-monitor proc-vmstat     --sub-heading numa_pte_updates      --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-numa-pte-updates.ps
			eval $GRAPH_PNG --title \"NUMA PTE Updates\"    --print-monitor proc-vmstat     --sub-heading numa_pte_updates      --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-numa-pte-updates-smooth.png --smooth
			eval $GRAPH_PSC --title \"NUMA PTE Updates\"    --print-monitor proc-vmstat     --sub-heading numa_pte_updates      --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-numa-pte-updates-smooth.ps --smooth

			eval $GRAPH_PNG --title \"NUMA Convergence\"    --print-monitor Numaconvergence                                   --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-numa-convergence.png
			eval $GRAPH_PSC --title \"NUMA Convergence\"    --print-monitor Numaconvergence                                   --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-numa-convergence.ps
			eval $GRAPH_PNG --title \"NUMA Hints Local\"    --print-monitor proc-vmstat --sub-heading numa_hint_faults_local  --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-numa-hints-local.png
			eval $GRAPH_PSC --title \"NUMA Hints Local\"    --print-monitor proc-vmstat --sub-heading numa_hint_faults_local  --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-numa-hints-local.ps
			eval $GRAPH_PNG --title \"NUMA Hints Local\"    --print-monitor proc-vmstat --sub-heading numa_hint_faults_local  --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-numa-hints-local-smooth.png --smooth
			eval $GRAPH_PSC --title \"NUMA Hints Local\"    --print-monitor proc-vmstat --sub-heading numa_hint_faults_local  --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-numa-hints-local-smooth.ps --smooth
			eval $GRAPH_PNG --title \"NUMA Hints Remote\"   --print-monitor proc-vmstat --sub-heading numa_hint_faults_remote --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-numa-hints-remote.png
			eval $GRAPH_PSC --title \"NUMA Hints Remote\"   --print-monitor proc-vmstat --sub-heading numa_hint_faults_remote --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-numa-hints-remote.ps
			eval $GRAPH_PNG --title \"NUMA Hints Remote\"   --print-monitor proc-vmstat --sub-heading numa_hint_faults_remote --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-numa-hints-remote-smooth.png --smooth
			eval $GRAPH_PSC --title \"NUMA Hints Remote\"   --print-monitor proc-vmstat --sub-heading numa_hint_faults_remote --output $OUTPUT_DIRECTORY/graph-$SUBREPORT-proc-vmstat-numa-hints-remote-smooth.ps --smooth


			echo "<tr>"
			smoothover graph-$SUBREPORT-numa-memory-balance
			smoothover graph-$SUBREPORT-proc-vmstat-pgmigrate_success
			smoothover graph-$SUBREPORT-proc-vmstat-numa-pte-updates
			echo "</tr>"
			echo "<tr>"
			plain graph-$SUBREPORT-numa-convergence
			smoothover graph-$SUBREPORT-proc-vmstat-numa-hints-local
			smoothover graph-$SUBREPORT-proc-vmstat-numa-hints-remote
			echo "</tr>"
		fi

		echo "</table>"
	fi
done
cat $SCRIPTDIR/shellpacks/common-footer-$FORMAT 2> /dev/null
