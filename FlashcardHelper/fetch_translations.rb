require 'open-uri'
require 'rexml/document'
require 'cgi'
require 'axlsx'
include REXML

outFilename = "flashcard_notes.xlsx"

class Hypothesis
  attr_accessor :priority, :translations, :category, :translationNote, :disambiguation, :language
end

def fetchPronunciation(word, language)
  pronUrl = "http://en.pons.com/translate?q=" + CGI.escape(word) + "&l=en" + language + "&in=" + language + "&lf=" + language
  pronPageContent = open(pronUrl) {|f| f.read}
  pronPageContent.gsub!(/\r\n?/, "\n")
  
  wordEscaped = CGI.escapeHTML(word)
  
  #puts wordEscaped
  #puts pronPageContent
  #puts pronUrl
  
  pronPageContent =~ /.*<h2>\s*#{wordEscaped}\s*(?:<span class=.flexion.>.{,100}<\/span>\s*)?<span class=.phonetics.>\[([^\]]*)\]<\/span> <span class=.wordclass.><acronym title=.noun.>NOUN<\/acronym><\/span>.*/m
  pronContent = $1
  
  #puts pronContent
  
  if !pronContent.nil?
    pronContent = pronContent.gsub(/<span class="separator">.<\/span>/, "")
    pronContent = pronContent.gsub(/ˈ/, "'")
  end
  
  return pronContent
end

class Translation
  attr_accessor :word, :gender, :hypotheses
  
  def eql?(other)
    (word == other.word) and (gender == other.gender)
  end
  
  def hash
    return 17 + word.hash * 37 + gender.hash * 97
  end
  
  def to_s
    out = word
    if !out.nil?
      out << ' (' + gender + ')'
      
      puts "xxx " + word if hypotheses.nil? or hypotheses.empty?
      
      pron = fetchPronunciation(word, hypotheses.first.language)
      out << " /" + pron + "/" if !pron.nil?
    end
    return out
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

writeInterval = 5
transSite = "http://www.wordreference.com"
languages = {"fr" => "/enfr/","it" => "/enit/","es" => "/es/translation.asp?tranword=","pt" => "/pten/"}

p = Axlsx::Package.new
book = p.workbook
sheet = book.add_worksheet(:name => "Notes")

row = []

row << "English Word"
languages.each_key do |lang|
  row << lang + " word"
  row << lang + " pronunciation"
end
sheet.add_row(row)

p.serialize outFilename

wordIdx = 1
enWords=File.open(ARGV[0]).read
enWords.gsub!(/\r\n?/, "\n")
enWords.each_line do |enWord|
  
  row = []
  
  enWord = enWord.strip
  row << enWord
  
  languages.each do |lang, path|
    hypotheses = []
    
    hypothesis = nil
    transUrl = transSite + path + CGI.escape(enWord)
    content = open(transUrl) {|f| f.read}
    content.gsub!(/\r\n?/, "\n")
    
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
                
                trans.hypotheses = [] if trans.hypotheses.nil?
                trans.hypotheses << hypothesis
                
                #trans.pronunciation = pronunciation(translation, lang)
                hypothesis.translations << trans if !translation.include?("title='translation unavailable'")
              end
              
              evennessTmp = groups[:evenness]
              
              hypothesis.priority = priority
              hypothesis.language = lang
              hypothesis.category = groups[:category]
              hypothesis.translationNote = groups[:translationNote]
              hypothesis.disambiguation = groups[:disambiguation]
              
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
        hypothesis.language = hypothesisOld.language
        
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
          
          trans.hypotheses = [] if trans.hypotheses.nil?
          trans.hypotheses << hypothesis
          
          hypothesis.translations << trans
        end # translation loop
        
        hypothesis.translationNote = contGroups[:translationNote]
        
        #puts "trans hypo: " + hypothesis.inspect
        
        hypotheses << hypothesis if !hypothesis.translations.empty?
      end # continued translation block if
      
      #hypotheses << hypothesis if !hypothesis.nil?
    end # translation line loop
    
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
      
      cellContent = ""
      breakPending = false
      if translations.length == 1
        cellContent << translations.first.to_s #if !translations.first.to_s.nil?
        breakPending = true
      elsif translations.length > 1
        translations.map.with_index do |candidate, i|
          cellContent << "\r\n---\r\n" if i > 0
          cellContent << candidate.to_s #if !candidate.to_s.nil?
          
          #puts enWord + " untranslated into " + lang if candidate.to_s.nil?
        end
        breakPending = true
      end # hypo count ifelse
      row << cellContent
      
=begin
      cellContent = ""
      translations.map.with_index do |candidate, i|
        cellContent << "|" if i > 0
        pron = pronunciation(candidate.word, lang)
        cellContent << pron if !pron.nil?
      end
      row << cellContent
=end
      
      break if breakPending
    end # hypo priority loop
  end
  
  sheet.add_row(row)
  wordIdx = (wordIdx + 1) % writeInterval
  p.serialize outFilename
  #if wordIdx == 0
  
  puts "Row complete: " + enWord
end

p.serialize outFilename