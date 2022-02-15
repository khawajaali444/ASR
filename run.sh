#!/bin/bash
. ./path.sh || exit 1
. ./cmd.sh || exit 1
nj=1 
lm_order=1 
. utils/parse_options.sh || exit 1
[[ $# -ge 1 ]] && { echo "Wrong arguments!"; exit 1; }
rm -rf exp mfcc gfcc data/train/spk2utt data/train/cmvn.scp data/train/feats.scp data/train/split1 data/test/spk2utt data/test/cmvn.scp data/test/feats.scp data/test/split1 data/local/lang data/lang data/local/tmp data/local/dict/lexiconp.txt

echo "..."
echo "..."
echo " Stage 1 PREPARING ACOUSTIC DATA and FEATURES EXTRACTION"
echo "..."
echo "..."


utils/utt2spk_to_spk2utt.pl data/train/utt2spk > data/train/spk2utt
utils/utt2spk_to_spk2utt.pl data/test/utt2spk > data/test/spk2utt



mfccdir=mfcc

steps/make_mfcc.sh --nj $nj --cmd "$train_cmd" data/train exp/make_mfcc/train $mfccdir
steps/make_mfcc.sh --nj $nj --cmd "$train_cmd" data/test exp/make_mfcc/test $mfccdir
steps/compute_cmvn_stats.sh data/train exp/make_mfcc/train $mfccdir
steps/compute_cmvn_stats.sh data/test exp/make_mfcc/test $mfccdir

echo "..."
echo "..."
echo " Stage 2 PREPARING LANGUAGE DATA"
echo "..."
echo "..."


utils/prepare_lang.sh data/local/dict "<UNK>" data/local/lang data/lang

echo "..."
echo "..."
echo " Stage 3 LANGUAGE MODEL CREATION and MAKING G.fst"
echo "..."
echo "..."

loc=`which ngram-count`;
if [ -z $loc ]; then
	if uname -a | grep 64 >/dev/null; then
		sdir=$KALDI_ROOT/tools/srilm/bin/i686-m64
	else
		sdir=$KALDI_ROOT/tools/srilm/bin/i686
	fi
	if [ -f $sdir/ngram-count ]; then
		echo "Using SRILM language modelling tool from $sdir"
		export PATH=$PATH:$sdir
	else
		echo "SRILM toolkit is probably not installed. Instructions: tools/install_srilm.sh"
		exit 1
	fi
fi
local=data/local
mkdir $local/tmp
ngram-count -order $lm_order -write-vocab $local/tmp/vocab-full.txt -wbdiscount -text $local/corpus.txt -lm $local/tmp/lm.arpa



lang=data/lang
arpa2fst --disambig-symbol=#0 --read-symbol-table=$lang/words.txt $local/tmp/lm.arpa > $lang/G.fst

echo "..."
echo "..."
echo " Stage 4 MONO TRAINING"
echo "..."
echo "..."

steps/train_mono.sh --nj $nj --cmd "$train_cmd" data/train data/lang exp/mono || exit 1

echo "..."
echo "..."
echo " Stage 5 MONO DECODING"
echo "..."
echo "..."

utils/mkgraph.sh --mono data/lang exp/mono exp/mono/graph || exit 1
steps/decode.sh --config conf/decode.config --nj $nj --cmd "$decode_cmd" exp/mono/graph data/test exp/mono/decode

echo "..."
echo "..."
echo " Stage 6 MONO ALIGNMENT"
echo "..."
echo "..."

steps/align_si.sh --nj $nj --cmd "$train_cmd" data/train data/lang exp/mono exp/mono_ali || exit 1

echo "..."
echo "..."
echo " Stage 7 TRI1 (first triphone pass) TRAINING"
echo "..."
echo "..."

steps/train_deltas.sh --cmd "$train_cmd" 2000 11000 data/train data/lang exp/mono_ali exp/tri1 || exit 1

echo "..."
echo "..."
echo " Stage 8 TRI1 (first triphone pass) DECODING"
echo "..."
echo "..."

utils/mkgraph.sh data/lang exp/tri1 exp/tri1/graph || exit 1
steps/decode.sh --config conf/decode.config --nj $nj --cmd "$decode_cmd" exp/tri1/graph data/test exp/tri1/decode

echo
echo "===== run.sh script is finished ====="
echo
