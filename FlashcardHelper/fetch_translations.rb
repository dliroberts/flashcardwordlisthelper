require 'open-uri'
require 'rexml/document'
require 'cgi'
require 'rubygems'
require 'roo'
include REXML

class Hypothesis
  attr_accessor :priority, :translations, :category, :translationNote, :disambiguation
end

class Translation
  attr_accessor :word, :gender, :pronunciation
  
  def eql?(other)
    (word == other.word) and (gender == other.gender)
  end
  
  def hash
    return 17 + word.hash * 37 + gender.hash * 97
  end
  
  def to_s
    word + ' (' + gender + ')'
  end
end
       
def posToGender(pos)
  gender = nil
  if ['nm','sm'].include?(pos)
    gender = 'm'
  elsif ['nf','sf'].include?(pos)
    gender = 'f'
  elsif pos == 'nmpl'
    gender = 'm pl'
  elsif pos == 'nfpl'
    gender = 'f pl'
  elsif pos == 'nm ou nf'
    gender = 'm/f'
  else
    gender = "unknown"
    #raise "Unsupported POS: " + pos
  end
  return gender
end

def pronunciation(word, language)
  pronUrl = "http://en.pons.com/translate?q=" + CGI.escape(word) + "&l=en" + language + "&in=" + language + "&lf=" + language
  pronPageContent = open(pronUrl) {|f| f.read}
  pronPageContent.gsub!(/\r\n?/, "\n")
  
  wordEscaped = CGI.escapeHTML(word)
  
  #puts wordEscaped
  #puts pronPageContent
  
  pronPageContent =~ /.*<h2>\s*#{wordEscaped}\s*<span class=.phonetics.>\[([^\]]*)\]<\/span> <span class=.wordclass.><acronym title=.noun.>NOUN<\/acronym><\/span>.*/m
  pronContent = $1
  if !pronContent.nil?
    pronContent = pronContent.gsub(/<span class="separator">.<\/span>/, "")
    pronContent = pronContent.gsub(/ˈ/, "'")
  end
  
  return pronContent
end

transSite = "http://www.wordreference.com"
languages = {"fr" => "/enfr/","it" => "/enit/","es" => "/es/translation.asp?tranword=","pt" => "/pten/"}

header = "enword\t"
languages.each_key do |lang|
  header << lang + "_trans\t"
  header << lang + "_pron\t"
end
puts header

enWords=File.open(ARGV[0]).read
enWords.gsub!(/\r\n?/, "\n")
enWords.each_line do |enWord|
  
  enWord = enWord.strip
  print enWord
  print "\t"
  
  languages.each do |lang, path|
    hypotheses = []
    
    hypothesis = nil
    transUrl = transSite + path + CGI.escape(enWord)
    content = open(transUrl) {|f| f.read}
    content.gsub!(/\r\n?/, "\n")
    
    #puts transUrl
    
    #print content
    
    content =~ /<!-- center column -->(.*)<!-- right column -->/m
    content = $1
    evennessTmp = nil
    
    priority = nil
    content.each_line do |line|
      
      # Section headings
      if line =~ /.*<td colspan='3' title='Principal Translations'.*/
        priority = 0
        evennessTmp = nil
        #puts "=== PRIORITY 0 (principal) ==="
      elsif line =~ /.*<td colspan='3' title='Compound Forms'.*/
        priority = 0
        evennessTmp = nil
        #puts "=== PRIORITY 0 (compound) ==="
      elsif line =~ /.*<td colspan='3' title='Additional Translations'.*/
        priority = 1
        evennessTmp = nil
        #puts "=== PRIORITY 1 ==="
      end
      
      # Beginning of translation block
      groups = line.match(/.*<tr class='(?<evenness>even|odd)' id='en#{lang}:\d+'><td class='FrWrd'><strong>(?<enWordsFound>.*)<\/strong> <em class='POS2'>(?<enPos>.*)<\/em><\/td><td>(?: <i class='Fr2'>(?<category>.*)<\/i>)? \((?<disambiguation>.*)\)(?: <i class='To2' >(?<translationNote>.*)<\/i>)?<\/td><td class='ToWrd' >(?<translations>.*) <em class='POS2'>(?<transPos>.*)<\/em><\/td><\/tr>/)
      contGroups = nil
      if evennessTmp != nil
        contGroups = line.match(/<tr class='#{evennessTmp}'><td>&nbsp;<\/td><td class='To2'>(?<translationNote>.*)<\/td><td class='ToWrd' >(?<translations>.*) <em class='POS2'>(?<transPos>.*)<\/em><\/td><\/tr>/)
      end
      
      if groups != nil
        if groups[:enPos] == "n"
          #puts "Trans block: " + line
          
          hypothesis = Hypothesis.new
          
          enWordsFound = groups[:enWordsFound]
          
          enWordsFound.split(", ").each do |enWordFound|
            if enWordFound == enWord
              posTmp = groups[:transPos]
              genderTmp = posToGender(posTmp)
              
              groups[:translations].split(", ").each do |translation|
                if hypothesis.translations.nil?
                  hypothesis.translations = []
                end
                trans = Translation.new
                trans.gender = genderTmp
                trans.word = translation
                trans.pronunciation = pronunciation(translation, lang)
                hypothesis.translations << trans
              end
              
              evennessTmp = groups[:evenness]
              
              hypothesis.priority = priority
              
              hypothesis.category = groups[:category]
              hypothesis.translationNote = groups[:translationNote]
              hypothesis.disambiguation = groups[:disambiguation]
              
              #puts "trans hypo: " + hypothesis.inspect
              
              hypotheses << hypothesis
            end
          end
        else
          evennessTmp = nil
        end
      elsif !evennessTmp.nil? and !contGroups.nil?
        hypothesisOld = hypothesis
        hypothesis = Hypothesis.new
        
        hypothesis.priority = hypothesisOld.priority
        
        pos = contGroups[:transPos]
        genderTmp = posToGender(pos)
        
        if hypothesis.translations.nil?
          hypothesis.translations = []
        end
        contGroups[:translations].split(", ").each do |translation|
          if translation == "-"
            next
          end
          trans = Translation.new
          trans.gender = genderTmp
          trans.word = translation
          hypothesis.translations << trans
        end # translation loop
        
        hypothesis.translationNote = contGroups[:translationNote]
        
        #puts "trans hypo: " + hypothesis.inspect
        
        hypotheses << hypothesis if !hypothesis.translations.empty?
      end # continued translation block if
      
      #hypotheses << hypothesis if !hypothesis.nil?
    end # translation line loop
    
    #puts hypotheses
    
    # Print translations - with disambiguation if necessary
    
    [0,1].each do |priority|
      # TODO go through in priority order
      
      # make merged list of all translations
      
      priorityHypotheses = hypotheses.select {|hypothesis| hypothesis.priority == priority}
      
      translations = Set.new
      #translations += priorityHypotheses.each {|priorityHypothesis| priorityHypothesis.translations}
      
      priorityHypotheses.each do |hyp|
        translations += hyp.translations
      end
      
      #puts translations.inspect
      
      breakPending = false
      if translations.length == 1
        print translations.first
        breakPending = true
      elsif translations.length > 1
        translations.map.with_index do |candidate, i|
          print "|" if i > 0
          print candidate.inspect
        end
        breakPending = true
      end # hypo count ifelse
      
      print "\t"
      translations.map.with_index do |candidate, i|
        print "oink"
        print "|" if i > 0
        print pronunciation(candidate.word, lang)
      end
      print "\t"
      break if breakPending
    end # hypo priority loop
    #exit # TODO remove - test only
  end 
  puts
end
