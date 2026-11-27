import { useCallback, useEffect, useMemo, useState } from "react";
import { View } from "react-native";

import {
  SchoolAttachments, SchoolCard, SchoolContent, SchoolPage, SchoolRow, useSchoolManager,
} from "@/components/pronote/SchoolPage";
import { CourseResource, LessonSummary } from "@/services/shared/timetable";
import { Capabilities } from "@/services/shared/types";
import Button from "@/ui/new/Button";
import Typography from "@/ui/new/Typography";

export default function PronoteLessons() {
  const { manager, revision, accountId } = useSchoolManager();
  const [reload, setReload] = useState(0);
  const [lessons, setLessons] = useState<LessonSummary[]>([]);
  const [selected, setSelected] = useState<LessonSummary>();
  const [subject, setSubject] = useState<string>();
  const [contents, setContents] = useState<CourseResource[]>([]);
  const [loading, setLoading] = useState(true);
  const [failure, setFailure] = useState("");
  const refresh = useCallback(() => setReload(value => value + 1), []);
  const subjects = useMemo(() => [...new Set(lessons.map(lesson => lesson.subject))].sort((a, b) => a.localeCompare(b, "fr")), [lessons]);
  const serviceIds = manager?.getAccount().services.map(service => service.id);

  useEffect(() => {
    setLessons([]);
    setSelected(undefined);
    setSubject(undefined);
    setContents([]);
  }, [accountId]);

  useEffect(() => {
    if (!manager) return;
    let active = true;
    const capable = manager.getAvailableClients(Capabilities.COURSE_RESOURCES);
    setLoading(capable.length > 0);
    setFailure("");
    if (!capable.length) {
      setLessons([]);
      setFailure("Le cahier de textes n’est pas disponible pour ce compte.");
      return;
    }
    const ids = manager.getAccount().services.filter(service => capable.some(client => "accountId" in client && client.accountId === service.id)).map(service => service.id);
    Promise.allSettled(ids.map(id => manager.getLessons(id))).then(results => {
      if (!active) return;
      const loaded = results.flatMap(result => result.status === "fulfilled" ? result.value : []);
      if (loaded.length || results.every(result => result.status === "fulfilled")) setLessons(loaded);
      if (results.some(result => result.status === "rejected")) setFailure("Une partie du cahier de textes n’a pas pu être chargée.");
      setLoading(false);
    });
    return () => { active = false; };
  }, [manager, revision, reload]);

  const [detailLoading, setDetailLoading] = useState(false);
  const [detailFailure, setDetailFailure] = useState(false);
  useEffect(() => {
    if (!manager || !selected || !manager.getAccount().services.some(service => service.id === selected.createdByAccount)) return;
    let active = true;
    setContents([]);
    setDetailLoading(true);
    setDetailFailure(false);
    manager.getLesson(selected).then(
      value => { if (active) setContents(value); },
      () => { if (active) setDetailFailure(true); },
    ).finally(() => { if (active) setDetailLoading(false); });
    return () => { active = false; };
  }, [manager, selected, reload]);

  const detail = selected && serviceIds?.includes(selected.createdByAccount) ? selected : undefined;
  const visibleLessons = lessons.filter(lesson => serviceIds?.includes(lesson.createdByAccount) && (!subject || lesson.subject === subject));
  if (detail) {
    return (
      <SchoolPage title={detail.subject} loading={detailLoading} refresh={refresh}>
        <Button label="Retour au cahier de textes" variant="text" onPress={() => setSelected(undefined)} />
        <Typography variant="h2">{detail.title || detail.subject}</Typography>
        <Typography color="textSecondary">{detail.date.toLocaleDateString("fr-FR", { dateStyle: "long" })}</Typography>
        {detail.teachers.length > 0 && <Typography color="textSecondary">{detail.teachers.join(", ")}</Typography>}
        {detailFailure && <Typography>Le détail de la leçon est momentanément indisponible.</Typography>}
        {!detailLoading && !detailFailure && contents.length === 0 && <Typography>Aucun contenu pour cette leçon.</Typography>}
        {contents.map((content, index) => (
          <SchoolCard key={index}>
            {content.title && <Typography variant="title">{content.title}</Typography>}
            {content.description && <SchoolContent content={content.description} />}
            <SchoolAttachments files={content.attachments} />
          </SchoolCard>
        ))}
      </SchoolPage>
    );
  }

  return (
    <SchoolPage title="Cahier de textes" loading={loading} refresh={refresh}>
      {failure && <Typography color="textSecondary">{failure}</Typography>}
      {!loading && !failure && !visibleLessons.length && <Typography>Aucune leçon publiée{subject ? " pour cette matière" : ""}.</Typography>}
      {subjects.length > 0 && !subject && (
        <View style={{ gap: 8 }}>
          <Typography variant="h4">Par matière</Typography>
          {subjects.map(name => <SchoolRow key={name} title={name} onPress={() => setSubject(name)} />)}
        </View>
      )}
      {subject ? <Button label="Toutes les matières" variant="text" onPress={() => setSubject(undefined)} /> : null}
      {subject && <Typography variant="h3">{subject}</Typography>}
      {subject && visibleLessons.map(lesson => (
        <SchoolRow key={lesson.createdByAccount + ":" + lesson.id} title={lesson.title || lesson.subject}
          caption={lesson.date.toLocaleDateString("fr-FR", { dateStyle: "long" }) + (lesson.hasHomework ? " · Devoir associé" : "")}
          onPress={() => setSelected(lesson)} />
      ))}
    </SchoolPage>
  );
}
