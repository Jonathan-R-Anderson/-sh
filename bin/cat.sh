#!/usr/bin/env sh

show_ends=0
number=0
number_nonblank=0
squeeze_blank=0
show_tabs=0
show_nonprinting=0

usage() {
    echo "Usage: $0 [OPTIONS] [FILE]..." >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -E|--show-ends) show_ends=1 ;;
        -n|--number) number=1 ;;
        -b|--number-nonblank) number_nonblank=1 ;;
        -s|--squeeze-blank) squeeze_blank=1 ;;
        -T|--show-tabs) show_tabs=1 ;;
        -v|--show-nonprinting) show_nonprinting=1 ;;
        -A|--show-all) show_ends=1; show_tabs=1; show_nonprinting=1 ;;
        -e) show_ends=1; show_nonprinting=1 ;;
        -t) show_tabs=1; show_nonprinting=1 ;;
        --help) usage ;;
        --) shift; break ;;
        -*) echo "$0: invalid option $1" >&2; usage ;;
        *) break ;;
    esac
    shift
done

if [ "$number_nonblank" -eq 1 ]; then
    number=0
fi

files="$@"
[ $# -eq 0 ] && files="-"

CAT_SHOW_ENDS=$show_ends CAT_NUMBER=$number CAT_NUMBER_NB=$number_nonblank \
CAT_SQUEEZE=$squeeze_blank CAT_SHOW_TABS=$show_tabs CAT_SHOW_NONPRINT=$show_nonprinting \
awk -f /usr/share/awk/ord.awk -f - $files <<'AWK'
BEGIN {
    show_ends=ENVIRON["CAT_SHOW_ENDS"]
    number=ENVIRON["CAT_NUMBER"]
    number_nb=ENVIRON["CAT_NUMBER_NB"]
    squeeze=ENVIRON["CAT_SQUEEZE"]
    show_tabs=ENVIRON["CAT_SHOW_TABS"]
    show_nonprint=ENVIRON["CAT_SHOW_NONPRINT"]
    line_num=1
    prev_blank=0
}
{
    line=$0
    blank=(length($0)==0)
    if(show_tabs) gsub(/\t/, "^I", line)
    if(show_nonprint){
        out=""
        for(i=1;i<=length($0);i++){
            c=substr($0,i,1)
            code=ord(c)
            if(c=="\t"||c=="\n")
                out=out c
            else if(code<32)
                out=out "^" sprintf("%c",code+64)
            else if(code==127)
                out=out "^?"
            else if(code>127){
                code-=128
                if(code<32) out=out "M-^" sprintf("%c",code+64)
                else if(code==127) out=out "M-^?"
                else out=out "M-" sprintf("%c",code)
            } else
                out=out c
        }
        line=out
    }
    if(show_ends) line=line"$"
    if(squeeze){
        if(blank){
            if(prev_blank) next
            prev_blank=1
        } else {
            prev_blank=0
        }
    }
    if(number_nb){
        if(blank)
            print line
        else {
            printf("%6d\t%s\n", line_num, line)
            line_num++
        }
    } else if(number){
        printf("%6d\t%s\n", line_num, line)
        line_num++
    } else {
        print line
    }
}
AWK

