#! /usr/bin/make

START=2011-12-18
END=2015-12-18

# Date,USD-per-BTC (from Coindesk's BPI: thanks!)
RATES := rates-$(START),$(END).csv

default: fee-rate-$(START),$(END).csv fixed-fees-$(START),$(END).csv tx-minouts-$(START),$(END).csv txsize-$(START),$(END).csv

# DATE,average-fee-rate-satoshi-per-k,average-fee-rate-cents-per-k
fee-rate-%.csv: txs-by-day-%.csv
	awk -F, '{ if (PREVDATE && $$1 != PREVDATE) { print PREVDATE "," TOTALFEES / TOTALSIZE * 1000 "," PREVRATE * TOTALFEES / TOTALSIZE * 1000; TOTALFEES=0; TOTALSIZE=0; } PREVDATE=$$1; TOTALSIZE+=$$2; TOTALFEES+=$$3; PREVRATE=$$5 } END { print PREVDATE "," TOTALFEES / TOTALSIZE * 1000 "," PREVRATE * TOTALFEES / TOTALSIZE * 1000 }' < $< > $@

# DATE,fixed-fee-txs,variable-fee-txs.
fixed-fees-%.csv: txs-by-day-%.csv
	awk -F, '{ if (PREVDATE && $$1 != PREVDATE) { print PREVDATE "," FIXED_FEES_TXS "," VAR_FEES_TXS; FIXED_FEES_TXS = 0; VAR_FEES_TXS = 0; } PREVDATE=$$1; if ($$3 % 1000 == 0) { FIXED_FEES_TXS++ } else { SAT_PER_KB_MOD=($$3 * 1000 / $$2) / 1000; if (SAT_PER_KB_MOD <= 2 || SAT_PER_KB_MOD >= 998) { FIXED_FEES_TXS++; } else { VAR_FEES_TXS++; } } } END { print PREVDATE "," FIXED_FEES_TXS "," VAR_FEES_TXS }' < $< > $@

# DATE,num-below-25c,num-below-$1,num-below-$5,num-above-$5.
tx-minouts-%.csv: txs-by-day-%.csv
	awk -F, '{ if (PREVDATE && $$1 != PREVDATE) { print PREVDATE "," NUM25 "," NUM100 "," NUM500 "," NUMOTHER; NUM25=0; NUM100=0; NUM500=0; NUMOTHER=0 } PREVDATE=$$1; AMOUNT=$$4 * $$5; if (AMOUNT < 25) NUM25++; else if (AMOUNT < 100) NUM100++; else if (AMOUNT < 500) NUM500++; else NUMOTHER++; } END { print PREVDATE "," NUM25 "," NUM100 "," NUM500 "," NUMOTHER }' < $< > $@

# DATE,average-bytes
txsize-%.csv: txs-by-day-%.csv
	awk -F, '{ if (PREVDATE && $$1 != PREVDATE) { print PREVDATE "," TOTALSIZE/NUMTXS; TOTALSIZE=0; NUMTXS=0; } PREVDATE=$$1; TOTALSIZE+=$$2; NUMTXS++ } END { print PREVDATE "," TOTALSIZE/NUMTXS }' < $< > $@

# Seconds,txid,size,fee,minoutput
TXS := txs-$(START),$(END).csv

default: $(RATES) $(TXS_BY_DAY)

rates-%.csv: close-%.json
	tr -s '{},' '\n' < $< | tr -d '"' | tr : , | grep '^2...-..-..,' > $@

close-%.json:
	START=`echo $* | cut -d, -f1`; END=`echo $* | cut -d, -f2`; wget -O $@ "http://api.coindesk.com/v1/bpi/historical/close.json?start=$$START&end=$$END"

blocktimes:
	../bitcoin-iterate/bitcoin-iterate -q --block=%bs,%bN > $@

blockrange-start-%: blocktimes
	START=$$(date -u +%s -d `echo $* | cut -d, -f1`); awk -F, "{ if (\$$1 >= $$START) { print \$$2; exit } }" < $< > $@

blockrange-end-%: blocktimes
	END=$$(date -u +%s -d `echo $* | cut -d, -f2`); awk -F, "{ if (\$$1 >= $$END) { print \$$2 - 1; exit } }" < $< > $@

# Blocktime,txid,size,fee,output (not including coinbases)
# awk filters for minimum output only.
txs-%.csv: blockrange-start-% blockrange-end-%
	../bitcoin-iterate/bitcoin-iterate --start=`cat blockrange-start-$*` --end=`cat blockrange-end-$*` -q --output=%tN,%bs,%th,%tl,%tF,%oa | grep -v '^0,' | cut -d, -f2- | awk -F, 'BEGIN { MINVAL=-1 } { if ($$2 != OLDTXID && HAVEOLD) { print MINOUT; MINVAL=-1 }; HAVEOLD=1; OLDTXID=$$2; if ($$5 < MINVAL || MINVAL < 0) { MINVAL=$$5; MINOUT=$$0; } } END { print MINOUT; }' > $@

# YYYY-MM-DD,size,fee,minoutput,US-cents-per-satoshi
# We filter timestamps so they don't go backwards.
txs-by-day-%.csv: txs-%.csv rate-append-%.awk
	awk -F, '{ if (PREVTIME && $$1 < PREVTIME) { TIME=PREVTIME; } else {TIME=$$1;} DATE=strftime("%Y-%m-%d",TIME,1); PREVTIME=TIME; print DATE "," $$3 "," $$4 "," $$5; }' < $< | awk -F, -f rate-append-$*.awk > $@

# For each date, append rate in cents-per-satoshi for that date.
rate-append-%.awk: rates-%.csv
	(echo -n "BEGIN { "; while IFS=, read DATE RATE; do echo -n "RATE[\"$$DATE\"] = \"`echo $$RATE / 1000000.0 | bc -l`\"; "; done < $<; echo '} { print $$0 "," RATE[$$1]; }') > $@
