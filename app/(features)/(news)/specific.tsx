import { NewsQuestionKind } from "@blockshub/pawnote-lts";
import { useLocalSearchParams } from "expo-router";
import { useTheme } from "expo-router/react-navigation";
import { useEffect, useRef, useState } from "react";
import { Alert, TextInput } from "react-native";

import { SchoolAttachments, SchoolCard, SchoolContent, SchoolPage, SchoolRow, useSchoolManager } from "@/components/pronote/SchoolPage";
import { addNewsToDatabase, getNewsById } from "@/database/useNews";
import { News, SurveyAnswer } from "@/services/shared/news";
import Button from "@/ui/new/Button";
import Typography from "@/ui/new/Typography";
import { cleanHtmlForArticle } from "@/utils/news/cleanUpHTMLNews";

export default function NewsPage() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { manager, accountId, revision } = useSchoolManager();
  const { colors } = useTheme();
  const [news, setNews] = useState<News>();
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [reload, setReload] = useState(0);
  const [answers, setAnswers] = useState<Record<string, SurveyAnswer>>({});
  const busy = useRef(false);
  const activeAccount = useRef(accountId);
  activeAccount.current = accountId;

  useEffect(() => {
    if (!id || !manager) return;
    let active = true;
    setLoading(true);
    setNews(undefined);
    setAnswers({});
    getNewsById(id).then(value => {
      if (active) setNews(value);
    }).catch(() => {
      if (active) setNews(undefined);
    }).finally(() => {
      if (active) setLoading(false);
    });
    return () => { active = false; };
  }, [id, manager, revision, reload]);

  const article = news && manager?.getAccount().services.some(service => service.id === news.createdByAccount) ? news : undefined;
  function confirmAction(survey: boolean) {
    if (!article || !manager || busy.current) return;
    Alert.alert(survey ? "Envoyer les réponses ?" : "Accuser réception ?", survey
      ? "Vos réponses seront envoyées à l’établissement."
      : "L’établissement sera informé que vous avez pris connaissance de cette information.", [
      { text: "Annuler", style: "cancel" },
      {
        text: survey ? "Envoyer" : "Confirmer",
        onPress: async () => {
          if (busy.current || activeAccount.current !== accountId) return;
          busy.current = true;
          setSending(true);
          try {
            const updated = survey
              ? await manager.submitNewsSurvey(article, Object.values(answers))
              : await manager.setNewsAsDone(article);
            if (activeAccount.current !== accountId) return;
            setNews(updated);
            if (!survey) await addNewsToDatabase([updated], false).catch(() => undefined);
          } catch {
            if (activeAccount.current === accountId) {
              Alert.alert("Envoi non confirmé", "Vérifiez l’état de cette actualité dans PRONOTE avant de réessayer.");
            }
          } finally {
            busy.current = false;
            setSending(false);
          }
        },
      },
    ]);
  }

  const survey = article?.survey;
  const ready = survey?.questions.filter(question => question.required).every(question => {
    const answer = answers[question.id];
    if (question.kind === NewsQuestionKind.TextInput) return Boolean(answer?.text?.trim());
    return Boolean(answer?.choices?.length);
  });

  return (
    <SchoolPage title={article?.type === "survey" ? "Sondage" : "Actualité"} loading={loading} refresh={() => setReload(value => value + 1)}>
      {!loading && !article && <Typography>Cette actualité n’a pas pu être chargée.</Typography>}
      {article && (
        <>
          <Typography variant="caption" color="textSecondary">{article.category}</Typography>
          <Typography variant="h2">{article.title || (article.type === "survey" ? "Sondage" : "Information")}</Typography>
          <Typography color="textSecondary">{[
            article.author,
            article.createdAt.getTime() > 0 ? article.createdAt.toLocaleDateString("fr-FR", { dateStyle: "long" }) : undefined,
          ].filter(Boolean).join(" · ")}</Typography>
          {article.content ? <SchoolContent content={cleanHtmlForArticle(article.content)} /> : null}
          <SchoolAttachments files={article.attachments} />
          {article.acknowledged && article.type === "information" && <Typography color="textSecondary">Réception confirmée</Typography>}
          {article.needsAcknowledgement && !article.acknowledged &&
            <Button label={sending ? "Confirmation…" : "Accuser réception"} onPress={() => confirmAction(false)} disabled={sending} />}
          {article.question && !survey && <Typography>Ce sondage n’a pas pu être chargé. Consultez-le dans PRONOTE.</Typography>}
          {article.fromCache && !article.content && !article.question && <Typography>Le texte sera disponible après synchronisation.</Typography>}
          {survey && (
            <>
              {survey.isAnonymous && <Typography color="textSecondary">Sondage anonyme</Typography>}
              {survey.questions.map((question, index) => (
                <SchoolCard key={question.id}>
                  <Typography variant="title">{question.title || "Question " + (index + 1)}</Typography>
                  {question.content && <SchoolContent content={question.content} />}
                  <SchoolAttachments files={question.attachments} />
                  {question.kind === NewsQuestionKind.TextInput && survey.canSubmit && question.required && (
                    <TextInput accessibilityLabel={question.title || "Réponse"} placeholder="Votre réponse"
                      multiline editable={!sending} maxLength={question.maximumLength}
                      value={answers[question.id]?.text ?? ""}
                      onChangeText={text => setAnswers(current => ({ ...current, [question.id]: { questionId: question.id, text } }))}
                      style={{ minHeight: 80, padding: 12, color: colors.text, backgroundColor: colors.background, borderRadius: 12 }} />
                  )}
                  {question.choices.map(choice => {
                    if (!survey.canSubmit || !question.required) return <Typography key={choice.position}>{choice.value}</Typography>;
                    const chosen = answers[question.id]?.choices ?? [];
                    const selected = chosen.includes(choice.position);
                    return <SchoolRow key={choice.position} title={choice.value} selected={selected} onPress={() => {
                      if (sending) return;
                      const choices = selected ? chosen.filter(value => value !== choice.position)
                        : question.kind === NewsQuestionKind.UniqueChoice ? [choice.position]
                        : chosen.length < (question.maximumChoices ?? question.choices.length) ? [...chosen, choice.position] : chosen;
                      setAnswers(current => ({ ...current, [question.id]: { questionId: question.id, choices } }));
                    }} />;
                  })}
                </SchoolCard>
              ))}
              {survey.answered && <Typography color="textSecondary">Réponses envoyées</Typography>}
              {survey.canSubmit && <Button label={sending ? "Envoi…" : "Envoyer mes réponses"} onPress={() => confirmAction(true)} disabled={!ready || sending} />}
              {!survey.canSubmit && !survey.answered && <Typography color="textSecondary">Pour répondre à ce sondage, ouvrez l’espace Élèves de PRONOTE.</Typography>}
            </>
          )}
        </>
      )}
    </SchoolPage>
  );
}
