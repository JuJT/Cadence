import { useEffect, useRef, useState } from "react";
import { Alert } from "react-native";

import { openSchoolLink, SchoolCard, SchoolContent, SchoolPage, SchoolRow, useSchoolManager } from "@/components/pronote/SchoolPage";
import type { AssessmentPeriod, AssessmentSection, ReportCard, SkillEvaluation } from "@/services/shared/assessment";
import { Capabilities } from "@/services/shared/types";
import { Services } from "@/stores/account/types";
import Button from "@/ui/new/Button";
import Typography from "@/ui/new/Typography";

const numberFormat = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 2 });

export default function AssessmentPage({ section }: { section: AssessmentSection }) {
  const skills = section === "skills";
  const title = skills ? "Compétences" : "Bulletins";
  const capability = skills ? Capabilities.SKILLS : Capabilities.REPORT_CARDS;
  const { manager, accountId, revision } = useSchoolManager();
  const [periods, setPeriods] = useState<AssessmentPeriod[]>([]);
  const [selected, setSelected] = useState<AssessmentPeriod>();
  const [evaluations, setEvaluations] = useState<SkillEvaluation[]>([]);
  const [report, setReport] = useState<ReportCard | null>(null);
  const [loadingPeriods, setLoadingPeriods] = useState(true);
  const [loadingDetail, setLoadingDetail] = useState(false);
  const [failure, setFailure] = useState("");
  const [detailError, setDetailError] = useState(false);
  const [retry, setRetry] = useState(0);
  const [creatingPDF, setCreatingPDF] = useState(false);
  const pdfRequest = useRef(false);
  const activeAccount = useRef(accountId);
  activeAccount.current = accountId;

  useEffect(() => {
    setPeriods([]);
    setSelected(undefined);
    setEvaluations([]);
    setReport(null);
    setFailure("");
  }, [accountId, section]);

  useEffect(() => {
    if (!manager) return;
    let active = true;
    setLoadingPeriods(true);
    setFailure("");
    const services = manager.getAccount().services.filter(service =>
      service.serviceId === Services.PRONOTE && manager.clientHasCapatibility(capability, service.id));
    if (services.length === 0) {
      setLoadingPeriods(false);
      setFailure("Cette rubrique n’est pas disponible pour ce compte.");
      return;
    }
    Promise.allSettled(services.map(service => manager.getAssessmentPeriods(section, service.id))).then(results => {
      if (!active) return;
      const loaded = results.flatMap(result => result.status === "fulfilled" ? result.value : []);
      setPeriods(loaded);
      setSelected(previous => (previous && loaded.find(row => row.serviceId === previous.serviceId && row.id === previous.id)) ?? loaded[0]);
      setLoadingPeriods(false);
      if (results.some(result => result.status === "rejected")) setFailure("Certaines périodes n’ont pas pu être chargées.");
    });
    return () => { active = false; };
  }, [manager, revision, retry, section, capability]);

  useEffect(() => {
    if (!manager || !selected || !manager.getAccount().services.some(service => service.id === selected.serviceId)) return;
    let active = true;
    setLoadingDetail(true);
    setDetailError(false);
    setReport(null);
    setEvaluations([]);
    const work = skills
      ? manager.getSkillEvaluations(selected).then(value => { if (active) setEvaluations(value); })
      : manager.getReportCard(selected).then(value => { if (active) setReport(value); });
    work.catch(() => { if (active) setDetailError(true); })
      .finally(() => { if (active) setLoadingDetail(false); });
    return () => { active = false; };
  }, [manager, selected, skills]);

  async function openPDF() {
    if (!manager || !report || !selected || pdfRequest.current) return;
    const current = accountId;
    pdfRequest.current = true;
    setCreatingPDF(true);
    try {
      const link = await manager.getReportCardPDF(selected);
      if (activeAccount.current === current) openSchoolLink(link);
    } catch {
      if (activeAccount.current === current) Alert.alert("PDF indisponible", "PRONOTE n’a pas pu générer ce bulletin.");
    } finally {
      pdfRequest.current = false;
      setCreatingPDF(false);
    }
  }

  const busy = loadingPeriods || loadingDetail;
  const visible = selected && manager?.getAccount().services.some(service => service.id === selected.serviceId);
  const labeledPeriods = periods.filter(period => manager?.getAccount().services.some(service => service.id === period.serviceId));
  return (
    <SchoolPage title={title} loading={busy} refresh={() => setRetry(value => value + 1)}>
      {failure && <Typography color="textSecondary">{failure}</Typography>}
      {labeledPeriods.length > 0 && (
        <SchoolCard>
          <Typography variant="title">Période</Typography>
          {labeledPeriods.map(period => (
            <SchoolRow key={period.serviceId + ":" + period.id} title={period.name}
              selected={period.id === selected?.id && period.serviceId === selected.serviceId}
              caption={period.start.toLocaleDateString("fr-FR", { month: "short", year: "numeric" })}
              onPress={() => {
                if (period === selected) return;
                setEvaluations([]);
                setReport(null);
                setLoadingDetail(true);
                setSelected(period);
              }} />
          ))}
        </SchoolCard>
      )}
      {!busy && !failure && !labeledPeriods.length && <Typography>Aucune période publiée dans cette rubrique.</Typography>}
      {detailError && <Typography>PRONOTE n’a pas pu charger cette période.</Typography>}
      {visible && !busy && !detailError && (
        skills ? (
          evaluations.length ? evaluations.map(item => (
            <SchoolCard key={item.id}>
              <Typography variant="caption" color="textSecondary">{item.subject} · {item.date.toLocaleDateString("fr-FR")}</Typography>
              <Typography variant="title">{item.title || "Évaluation"}</Typography>
              {item.teacher && <Typography color="textSecondary">{item.teacher}</Typography>}
              {item.description && <SchoolContent content={item.description} />}
              {item.skills.map((skill, index) => (
                <SchoolCard key={skill.id + ":" + index}>
                  <Typography variant="title">{skill.name}</Typography>
                  {skill.domain !== skill.name && <Typography color="textSecondary">{skill.domain}</Typography>}
                  <Typography>{skill.level || skill.abbreviation || "Niveau non communiqué"}</Typography>
                </SchoolCard>
              ))}
            </SchoolCard>
          )) : <Typography>Aucune évaluation publiée pour cette période.</Typography>
        ) : report ? (
          <>
            {report.overall.length > 0 && (
              <SchoolCard>
                <Typography variant="h4">Appréciations générales</Typography>
                {report.overall.map((item, index) => (
                  <SchoolContent key={index} content={item.name ? item.name + " · " + item.value : item.value} />
                ))}
              </SchoolCard>
            )}
            {report.subjects.map((item, index) => (
              <SchoolCard key={item.name + ":" + index}>
                <Typography variant="title">{item.name}</Typography>
                {item.group && item.group !== item.name && <Typography color="textSecondary">{item.group}</Typography>}
                {item.average !== undefined && <Typography>Moyenne indiquée par PRONOTE {numberFormat.format(item.average)}</Typography>}
                {item.classAverage !== undefined && <Typography color="textSecondary">Classe {numberFormat.format(item.classAverage)}</Typography>}
                {item.assessments.map((text, index) => <SchoolContent key={index} content={text} />)}
              </SchoolCard>
            ))}
            {!report.overall.length && !report.subjects.length && <Typography>Aucune appréciation ni moyenne publiée pour cette période.</Typography>}
            <Button label={creatingPDF ? "Génération…" : "Ouvrir le PDF du bulletin"} disabled={creatingPDF} onPress={() => void openPDF()} />
          </>
        ) : <Typography>Aucun bulletin n’est publié pour cette période.</Typography>
      )}
    </SchoolPage>
  );
}
